# 05 — Conditionals, Loops, Tags & Import vs Include

> ⏱️ **Time to complete: ~2 hrs** — read 25 min · practice 75 min · self-quiz 20 min
> 📦 **Covers:** `when` & Jinja2 tests · loops, dict2items, loop_control · until/retries/delay retry pattern · tags & the handler gotcha · **import vs include (the trap question)** · delegate_to / run_once / local_action · an LB-orchestrated rolling play

> **Interview framing:** Control flow is where playbook code becomes *engineering*: OS-specific logic, batch operations, retry semantics, and the classic **import vs include** trap question.

---

## 1. `when` — conditional execution

```yaml
tasks:
  - name: Install nginx on Debian family
    ansible.builtin.apt:
      name: nginx
      state: present
    when: ansible_facts['os_family'] == "Debian"

  - name: Install nginx on RHEL family
    ansible.builtin.dnf:
      name: nginx
      state: present
    when: ansible_facts['os_family'] == "RedHat"

  - name: Multi-condition (AND via list = all must hold)
    ansible.builtin.command: /opt/app/migrate
    when:
      - ansible_facts['distribution_major_version'] | int >= 20
      - env | default('dev') == "prod"
      - migrate_enabled | bool

  - name: OR / grouping
    ansible.builtin.debug: { msg: "dr or canary" }
    when: (dr_mode | default(false)) or ('canary' in group_names)

  - name: Skip on check mode
    ansible.builtin.uri: { url: "http://x/health", status_code: 200 }
    when: not ansible_check_mode
```

### Tests that make you sound experienced

```yaml
when: backup_dir is defined
when: result.rc not in [0, 1]
when: result is succeeded          # also: failed, changed, skipped
when: app_version is version('2.0', '>=')          # semantic version compare!
when: config_text is search('listen 443')          # regex search / match
when: db.host is match('^db-[0-9]+')
when: tags is contains('critical')                 # list contains
when: ansible_facts['os_family'] in ['RedHat', 'Suse']
when: my_list is subset(groups['web'])
```

> ⚠️ **The trap:** `when` + `loop` → the condition is evaluated **once per item**, with `item` available. People who say "when runs before the loop" fail the question.

---

## 2. Loops — `loop` (modern) not `with_*` (legacy)

```yaml
- name: Install several packages
  ansible.builtin.apt:
    name: "{{ item }}"
    state: present
  loop:
    - nginx
    - curl
    - git

- name: Loop a dict — dict2items
  ansible.builtin.user:
    name: "{{ item.key }}"
    state: present
    comment: "{{ item.value.fullname }}"
  loop: "{{ users | dict2items }}"
  vars:
    users:
      alice: { fullname: "Alice A" }
      bob:   { fullname: "Bob B" }

- name: Loop with index & friendly labels
  ansible.builtin.uri:
    url: "http://{{ item }}:8080/healthz"
  loop: "{{ groups['api'] }}"
  loop_control:
    label: "{{ item }}"        # readable output
    index_var: idx
    pause: 2                   # seconds between iterations (rate limiting!)
  register: healths

- name: Flatten nested loops
  ansible.builtin.debug: { msg: "{{ item.0 }} listens on {{ item.1 }}" }
  loop: "{{ vhosts | product(['80','443']) | list }}"
  vars: { vhosts: [app, admin] }
```

### Retry loop — `until` (the reliability pattern)

```yaml
- name: Wait until endpoint is healthy
  ansible.builtin.uri:
    url: "http://localhost:8080/healthz"
    status_code: 200
  register: health
  until: health.status == 200
  retries: 10          # total attempts (not extra!)
  delay: 5             # seconds between attempts
```

> 💬 **Say:** *"This is my standard flakiness guard for anything with external dependency — service boots, flaky downloads, transient APIs. It converts false negatives into eventual success and keeps the playbook honest if it truly never comes up."*

### 🎬 SCENARIO — batch file processing with failed-item harvesting

```yaml
- name: Migrate legacy configs
  ansible.builtin.command: /usr/local/bin/migrate "{{ item }}"
  loop: "{{ lookup('fileglob', 'configs/*.conf', wantlist=True) }}"
  register: migrations
  ignore_errors: true            # keep going on individual failures
  changed_when: "'migrated' in migrations.stdout | default('')"   # careful: per-item in .results

- name: Report the casualties
  ansible.builtin.debug:
    msg: "FAILED: {{ item.item }}"
  loop: "{{ migrations.results }}"
  when: item is failed           # .results[] per item — register+loop interaction
```

---

## 3. Tags — running slices of a playbook

```yaml
tasks:
  - name: Install packages
    ansible.builtin.apt: { name: nginx, state: present }
    tags: [install, packages]

  - name: Render config
    ansible.builtin.template: { src: nginx.conf.j2, dest: /etc/nginx/nginx.conf }
    notify: Reload nginx
    tags: config
```

```bash
ansible-playbook site.yml --tags config
ansible-playbook site.yml --tags config --skip-tags slow
ansible-playbook site.yml --list-tags
ansible-playbook site.yml --tags all --skip-tags never-run
```

Semantics you must know:
- `always` tag runs even with `--tags x`; `never` runs only if explicitly requested.
- **Tags do NOT trigger handlers**: `--tags config` runs the template task, but the notified reload will not fire (handler wasn't tagged). Tag the handler too, or use `--force-handlers` understanding — classic gotcha.
- `import`ed files: tags on the import statement apply to **every task inside**. `include`ed: only the include statement is tagged.
- Best practice — tag at **task level with fine categories** (`install`, `config`, `deploy`, `migrate`, `verify`) so operators can do surgical reruns: *"just re-push config without reinstalling"*.

---

## 4. Import vs include — THE trap question

| | `import_*` (static) | `include_*` (dynamic) |
|---|---|---|
| When processed | **Parse time** (playbook is read) | **Runtime** (when reached) |
| `--list-tasks` shows inner tasks? | ✅ yes, individually | ❌ shows the include as one line |
| Loops around it | ❌ not supported | ✅ `include_tasks` in a loop works |
| `when` on the statement | Applied to **every** child task (still evaluated per host, but stated once) | Evaluated **once** for the include decision |
| Tags on statement | Inherited by all children | Only gates the include itself |
| Conditional file names | Must be known at parse time | Can be computed (`include_tasks: "{{ tpl }}"`) |
| Handlers | `import_tasks` inside handler: child tasks become handlers | included file = one handler |

```yaml
tasks:
  - name: Static — task list is fixed
    ansible.builtin.import_tasks: tasks/firewall.yml

  - name: Dynamic — file decided at runtime
    ansible.builtin.include_tasks: "tasks/{{ ansible_facts['os_family'] | lower }}.yml"
```

Same duality for roles: **`import_role`** (static, tagged at parse time) vs **`include_role`** (dynamic, usable in loops/conditionals).

> 💬 **The senior soundbite:** *"Default to `import_*` for static structure — better `--list-tasks`, better linting, tags behave intuitively. Reach for `include_*` when you need runtime decisions: computed filenames, looping over fragments, or conditional loading. And remember: `when` on an import statement gets stamped on every imported task, which surprises people when a skipped-looking include still evaluates conditions per task."*

### 🎬 SCENARIO — OS-specific task files loaded dynamically

```
tasks/
├── Debian.yml
├── RedHat.yml
└── common.yml
```

```yaml
- name: Platform-specific firewall setup
  hosts: all
  become: true
  tasks:
    - name: Load common baseline
      ansible.builtin.import_tasks: tasks/common.yml

    - name: Load distro firewall tasks
      ansible.builtin.include_tasks: "tasks/{{ ansible_facts['os_family'] }}.yml"
      # Debian.yml uses ufw; RedHat.yml uses firewalld — file chosen at runtime
```

---

## 5. `delegate_to`, `run_once`, `local_action` — orchestration primitives

```yaml
# Run on a DIFFERENT host than the loop target
- name: Disable node in load balancer
  ansible.builtin.command: >
    haproxy-cli disable server web_pool/{{ inventory_hostname }}
  delegate_to: lb1

# Run once for the whole group, but facts/vars can still be relevant
- name: Cluster-wide schema migration (once!)
  ansible.builtin.command: /opt/db/bin/migrate --up
  run_once: true
  delegate_to: "{{ groups['db'][0] }}"

# Shortcut for delegate_to: localhost
- name: Register DNS
  community.general.nsupdate: ...
  delegate_to: localhost
  # equivalent: local_action: module args
```

Semantics: `delegate_to` changes **where the module runs** but NOT the facts/vars context (still the original host's) unless you add `delegate_facts: true`. `become` applies to the delegation target.

### 🎬 SCENARIO — rolling deploy orchestrated through an LB (preview of file 10)

```yaml
- hosts: web
  serial: 1                       # one host at a time
  tasks:
    - name: Drain from LB
      ansible.builtin.uri:
        url: "http://{{ hostvars[groups['lb'][0]].ansible_host }}:9999/drain/{{ inventory_hostname }}"
        method: POST
      delegate_to: localhost
      changed_when: true

    - name: Wait for connections to drain
      ansible.builtin.pause: { seconds: 10 }

    - name: Deploy new release
      ansible.builtin.import_tasks: tasks/deploy.yml

    - name: Health check locally
      ansible.builtin.uri: { url: "http://localhost:8080/healthz", status_code: 200 }

    - name: Re-enable in LB
      ansible.builtin.uri:
        url: "http://{{ hostvars[groups['lb'][0]].ansible_host }}:9999/enable/{{ inventory_hostname }}"
        method: POST
      delegate_to: localhost
```

---

## 6. 🎤 SDE-3 Interview Corner

**Q1. `when` with `loop` — how many evaluations?**
> Once per item, with `item` bound. To conditionally skip the *whole* loop, put `when` on an `include_tasks` wrapper or compute the list first: `loop: "{{ items | selectattr('enabled') | list }}"`.

**Q2. Why is `include_tasks` in a loop allowed but `import_tasks` isn't?**
> Imports resolve at parse time — there's no "loop time". Includes resolve at runtime, so each iteration can load the file. Same reason `when` on import stamps all children.

**Q3. How do you restart services only when config changed, but make sure it happens even mid-deploy?**
> `notify` + `meta: flush_handlers`. And if the play can fail before handlers: wrap in `block` with `always: [meta: flush_handlers]` or rely on `--force-handlers` at platform level.

**Q4. A task must run only on one host of a cluster but needs data from all hosts — pattern?**
> `run_once: true` (it still sees the whole batch via `ansible_play_hosts`), combined with `hostvars[...]` for per-host data. For facts from others: `delegate_facts` or pre-gather with a setup play.

**Q5. `until` vs `retries` module param vs `wait_for`?**
> `until/retries/delay` = generic poll-unto-success on any task. `wait_for` = purpose-built port/file/path/pattern waiter, no retry semantics needed. `wait_for_connection` = waits for SSH itself (post-reboot). Use each for its intent.

**Q6. Tags + handlers: config-only run didn't reload the service. Why? What do you do?**
> Handler ran only if the notify was processed — with `--tags config` the handler (untagged) is filtered out. Fix: tag handlers identically, or run full play, or accept it and note `meta: flush_handlers` is also tag-filtered. It's a deliberate scoping feature, not a bug.

---

## ⚠️ Common pitfalls

- `when: var == "true"` comparing string to boolean — normalize with `| bool` and quote YAML.
- `loop` over a **string** instead of list (single iteration with whole string as item) — ensure `wantlist=True` on single-value lookups or wrap in `[]`.
- `ignore_errors` hides real breakage — always pair with `register` and an explicit follow-up decision.
- `delegate_to` + `become: true` escalating on the *delegated* host unexpectedly.
- Tagging everything `always` → `--skip-tags` becomes useless; keep tag taxonomy small and documented.
- `loop_control.label` leaking secrets into logs — keep labels generic.

---

**➡️ Next:** [06 — Jinja2 Templates & Lookups](06-jinja2-templates.md)
