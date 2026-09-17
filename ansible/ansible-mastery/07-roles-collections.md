# 07 — Roles, Collections & Ansible Galaxy (Reusable Engineering)

> ⏱️ **Time to complete: ~2.5 hrs** — read 25 min · build the nginx role 105 min · self-quiz 20 min
> 📦 **Covers:** role anatomy tree · building a data-driven nginx role end-to-end · defaults vs vars precedence · role params · meta/main.yml & dependencies · collections, FQCN & requirements.yml pinning · mature repo layout · the one-role-many-topologies pattern

> **Interview framing:** "How do you structure a big Ansible codebase?" Roles are the answer — and the defaults-vs-vars + role-anatomy questions separate practitioners from tourists.

---

## 1. Role anatomy (memorize the tree)

```
roles/nginx/
├── defaults/          # LOWEST precedence — safe, overridable knobs
│   └── main.yml
├── vars/              # HIGH precedence — internal constants (do not override)
│   └── main.yml
├── tasks/             # the logic; main.yml is the entrypoint
│   ├── main.yml
│   ├── install.yml
│   └── configure.yml
├── handlers/
│   └── main.yml
├── templates/         # .j2 files
├── files/             # static files
├── meta/              # role metadata + dependencies
│   └── main.yml
├── library/           # role-local custom modules
├── module_defaults/
└── README.md          # document your knobs — senior habit
```

`scaffold it`:

```bash
ansible-galaxy init roles/nginx
```

---

## 2. 🎬 SCENARIO — Build a production `nginx` role from scratch

**`defaults/main.yml`** — the public API of the role:

```yaml
nginx_worker_processes: auto
nginx_user: www-data
nginx_vhosts: []            # [{ name: app.example.com, port: 80, upstream: "api:8080" }]
nginx_remove_default: true
nginx_packages: [nginx]
```

**`vars/main.yml`** — internals consumers shouldn't touch:

```yaml
nginx_conf_path: /etc/nginx/nginx.conf
nginx_vhost_dir: /etc/nginx/conf.d
```

**`tasks/main.yml`** — the entrypoint, importing sub-files:

```yaml
- name: Install packages
  ansible.builtin.import_tasks: install.yml

- name: Configure
  ansible.builtin.import_tasks: configure.yml

- name: Service
  ansible.builtin.import_tasks: service.yml
```

**`tasks/install.yml`**:

```yaml
- name: Install nginx packages
  ansible.builtin.package:
    name: "{{ nginx_packages }}"
    state: present
```

**`tasks/configure.yml`** — data-driven config:

```yaml
- name: Render main config
  ansible.builtin.template:
    src: nginx.conf.j2
    dest: "{{ nginx_conf_path }}"
    validate: "nginx -t -c %s"
  notify: Reload nginx

- name: Remove default site
  ansible.builtin.file:
    path: /etc/nginx/sites-enabled/default
    state: absent
  when: nginx_remove_default | bool
  notify: Reload nginx

- name: Manage vhosts (one file each)
  ansible.builtin.template:
    src: vhost.conf.j2
    dest: "{{ nginx_vhost_dir }}/{{ item.name }}.conf"
    validate: "nginx -t -c %s"
  loop: "{{ nginx_vhosts }}"
  loop_control: { label: "{{ item.name }}" }
  notify: Reload nginx
```

**`handlers/main.yml`**:

```yaml
- name: Reload nginx
  ansible.builtin.service:
    name: nginx
    state: reloaded
  listen: "reload webserver"        # topic-based notify
```

**Consuming it — three ways:**

```yaml
# A. Simple
- hosts: web
  roles:
    - nginx

# B. With params (a "role instantiation" — same role, two configs!)
- hosts: web
  roles:
    - role: nginx
      vars:
        nginx_vhosts:
          - name: app.example.com
            port: 80
            upstream: "api1:8080"

# C. Dynamic (runtime decisions, loops, when)
- hosts: web
  tasks:
    - ansible.builtin.include_role:
        name: nginx
      when: deploy_web | bool
      loop: "{{ instances }}"
      loop_control: { loop_var: instance }
```

And the playbook that uses it with fleet data:

```yaml
- name: Web tier
  hosts: web
  roles:
    - role: nginx
      vars:
        nginx_vhosts: "{{ vhost_config }}"   # comes from group_vars/web.yml
```

> 💬 **The interview story:** *"Roles turn playbooks into a library. My `nginx` role is data-driven — I declare WHAT vhosts exist in `group_vars`, the role owns HOW. The same role deploys a 3-vhost staging box and a 40-vhost edge LB. Defaults expose knobs, vars protect internals, handlers batch reloads, validate prevents bad deploys."*

---

## 3. `defaults` vs `vars` (the question everyone asks)

| | `defaults/main.yml` | `vars/main.yml` |
|---|---|---|
| Precedence | **Lowest** (only above nothing) | **High** (above play vars_files) |
| Purpose | Public, overridable knobs | Private constants |
| Consumer can override? | Encouraged — from any layer | Practically no |
| Analogy | Function default arguments | Local `const` |

Extra nuance to drop: role **params** (the `vars:` under `roles:`) beat `vars/main.yml`, which beats `vars_files`, which beats play vars, which beats defaults. That's the full role-visibility chain.

## 4. `meta/main.yml` — dependencies & metadata

```yaml
galaxy_info:
  author: platform-team
  description: Production nginx role
  license: MIT
  min_ansible_version: "2.15"
  platforms:
    - name: Ubuntu
      versions: [jammy]
    - name: EL
      versions: [9]

dependencies:
  - role: common            # always applied first
  - role: firewall
    vars: { open_ports: [80, 443] }
    when: manage_firewall | default(true) | bool   # conditional dep
  - role: hardening
    tags: [security]        # deps inherit parent tags in imports
```

> ⚠️ Dependency gotcha: the same role can run twice as a dependency only if `allow_duplicates: true`. Deps run **before** the parent role, in listed order.

---

## 5. Collections — the modern packaging unit

```bash
ansible-galaxy collection install community.docker
ansible-galaxy collection install -r requirements.yml
```

```yaml
# requirements.yml — pin EVERYTHING (reproducibility!)
---
roles:
  - name: geerlingguy.nginx
    version: 3.1.4            # semver pin — never 'latest' in prod
  - name: https://gitlab.internal/infra/role-base.git
    scm: git
    version: v1.2.0

collections:
  - name: community.docker
    version: ">=3.4.0,<4.0.0"
  - name: kubernetes.core
    version: 2.4.0
  - name: ansible.posix
```

**FQCN** (Fully Qualified Collection Name) — required habit:

```text
ansible.builtin.copy       # engine modules
community.general.ufw
community.docker.docker_container
kubernetes.core.k8s
amazon.aws.ec2_instance
ansible.posix.authorized_key
```

> 💬 **Say:** *"Unqualified names are ambiguous once multiple collections exist — `docker_container` could resolve differently depending on installed collections and redirects. FQCN is grep-able, unambiguous, and ansible-lint enforces it. Our CI fails on non-FQCN."*

Collections can also package **roles, filter/lookup/callback plugins, and modules** — i.e., a collection is your team's distributable automation library.

### Repo layout for a mature codebase

```
ansible-repo/
├── ansible.cfg
├── ansible-navigator.yml      # if using EEs (file 15)
├── requirements.yml           # pinned external deps
├── inventories/{production,staging}/...
├── site.yml                   # entrypoint playbook (just imports)
├── playbooks/                 # per-purpose plays
├── roles/                     # internal roles
│   ├── common/
│   ├── nginx/
│   └── postgres/
└── collections/               # vendored if air-gapped
```

```yaml
# site.yml — thin orchestration layer
- import_playbook: playbooks/web.yml
- import_playbook: playbooks/db.yml
```

---

## 6. 🎬 SCENARIO — Same role, two very different consumers

> *"One `postgres` role must serve a tiny staging VM and a 3-node production cluster. How?"*

```yaml
# playbooks/db.yml
- name: Postgres everywhere
  hosts: db
  roles:
    - role: postgres
      vars:
        pg_version: "{{ pg_version_override | default('15') }}"
        pg_max_connections: "{{ 100 if 'staging' in group_names else 500 }}"
        pg_replication:
          enabled: "{{ groups['db'] | length > 1 }}"
          primary: "{{ groups['db'][0] }}"
          replicas: "{{ groups['db'][1:] | default([]) }}"
```

The role internally branches on `pg_replication.enabled` (file 05's include pattern) — **one role, N topologies, zero forks of the role**. Interviewers love this because it demonstrates data-driven design instead of copy-paste roles.

---

## 7. 🎤 SDE-3 Interview Corner

**Q1. Role vs collection vs playbook?**
> Playbook = executable orchestration. Role = reusable component (tasks/vars/files bundled). Collection = distributable package that can contain roles + plugins + modules with its own versioning/namespace. Mature orgs: collections for shared libraries, roles for services, thin playbooks glueing them per environment.

**Q2. How do role dependencies resolve? Where do their vars come from?**
> Deps run first, in order, before the parent. Vars passed to a dep via `vars:` sit at role-param precedence. `allow_duplicates` controls re-runs; `when` on a dep gates it. Deps inherit tags from parent import statements — sometimes annoyingly.

**Q3. You need a role to behave differently on Ubuntu vs RHEL — cleanest mechanism?**
> `vars/{{ ansible_facts['os_family'] }}.yml` via `include_vars` (auto-matching first_found pattern), plus `include_tasks` per family for differing logic. Package names/paths in family vars; never sprinkle `when` everywhere.

**Q4. How do you version and share internal roles?**
> Git-tag semver + `requirements.yml` pins; internal Galaxy/Nexus/Artifactory mirror for air-gapped; roles reviewed via MR + Molecule CI (file 14); consumers pin exact or bounded-range versions. Never depend on `main` of someone else's repo.

**Q5. Why is a role's `vars/main.yml` bad place for something like `nginx_port`?**
> It overrides group_vars/play vars — consumers can't tune it without editing the role. That belongs in defaults. `vars/` is for computed internals (paths derived from defaults).

---

## ⚠️ Common pitfalls

- Putting overridable config in `vars/main.yml` — the classic "why can't I override this?" bug.
- Role names without FQCN when published inside a collection; local `roles/` names colliding with Galaxy roles.
- `dependencies:` loops (A→B→A) — parse explodes; keep the dep graph a DAG.
- Forgetting `meta/main.yml` platforms → role looks broken on unsupported OS.
- Giant "god roles" doing 10 jobs — split by concern (install/configure/service), compose via deps.

---

**➡️ Next:** [08 — Error Handling, Blocks & Rollbacks](08-error-handling.md)
