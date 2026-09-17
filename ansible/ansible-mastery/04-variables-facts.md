# 04 — Variables, Facts & Precedence (The #1 Interview Topic)

> ⏱️ **Time to complete: ~2 hrs** — read 25 min · precedence drills 75 min · self-quiz 20 min
> 📦 **Covers:** variable families (scalars, lists, dicts) · the full precedence ladder + a 60-second proof lab · facts & gathering subsets · custom facts (ansible_local) · magic vars (hostvars, groups, omit) · set_fact & cacheable facts · cross-host data patterns · the multi-env repo layout · debugging variable soup

> **Interview framing:** "If `-e` and `set_fact` collide, who wins?" If you can't answer instantly, this file is for you. Precedence questions appear in nearly every Ansible interview because they expose whether you've debugged real var soup.

---

## 1. The four families of variables

```yaml
# 1. Simple
app_name: api
http_port: 8080

# 2. Lists
packages:
  - nginx
  - curl

# 3. Dicts/mappings
db:
  host: db1.internal
  port: 5432
  name: orders
# access: {{ db.host }}  or  {{ db['host'] }}   (brackets when key has dots/dashes)

# 4. Nested structures (hostvars, results…) — same access rules
```

**Host scope:** every variable in Ansible belongs to a **host**. `group_vars` and `host_vars` are just convenient ways to define per-host values. This single sentence explains precedence.

---

## 2. The precedence ladder (the answer you must know cold)

Officially there are ~22 levels. **Don't memorize all 22 — memorize the anchor points and the golden rule.**

```
HIGHEST   ┌ 1. extra vars (-e / -extra-vars)            ─ ALWAYS wins, final
          │ 2. include params / role params
          │ 3. set_fact & registered vars               ─ runtime discoveries
          │ 4. include_vars (dynamically loaded files)
          │ 5. task vars → block vars
          │ 6. role vars (vars/main.yml)
          │ 7. play vars_files
          │ 8. play vars / vars_prompt
          │ 9. host facts (gathered) & cached set_fact
          │ 10. host_vars (playbook dir)
          │ 11. host_vars (inventory dir)
          │ 12. group_vars (playbook dir)
          │ 13. group_vars (inventory dir)
          │ 14. inventory [group:vars] / parsed inventory vars
LOWEST    └ 15. role defaults (defaults/main.yml)       ─ safest defaults live here
```

**The three-line answer for interviews:**

> *"Extra vars always win. `set_fact`/registered vars beat everything defined statically. Role defaults are the weakest — they exist so a role works out of the box but yields to every override. In between, the rule is: **more specific beats more general** (host beats group, child group beats parent, task beats play)."*

### 🎬 SCENARIO — prove it in 60 seconds

```yaml
- name: precedence lab
  hosts: localhost
  connection: local
  gather_facts: false
  vars:
    env: "play"
  tasks:
    - name: task-level override
      ansible.builtin.debug:
        msg: "env is {{ env }}"
      vars:
        env: "task"                  # → prints "task" (task beats play)

    - name: set_fact beats play vars
      ansible.builtin.set_fact: { env: "setfact" }

    - ansible.builtin.debug:
        msg: "env is now {{ env }}"  # → "setfact"

    - name: but -e beats set_fact
      ansible.builtin.debug:
        msg: "run with -e env=extra → prints extra"
```

```bash
ansible-playbook lab.yml
ansible-playbook lab.yml -e "env=extra"    # everything prints "extra"
```

---

## 3. Facts — discovered variables

`gather_facts: true` runs the `setup` module. Useful ones:

| Fact | Meaning |
|---|---|
| `ansible_facts['distribution']` / `_major_version` / `os_family` | OS routing (`RedHat`, `Debian`, `Ubuntu`) |
| `ansible_facts['default_ipv4']['address']` | primary IP |
| `ansible_facts['memtotal_mb']`, `processor_count` | capacity |
| `ansible_facts['fqdn']` | identity |
| `ansible_date_time.iso8601` | timestamps |

Modern style (2.5+): use the **`ansible_facts` dict**, not underscore-prefixed globals — both work, the dict is lint-clean:

```yaml
- ansible.builtin.debug:
    msg: "{{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }}"
```

**Performance control** (file 11 expands):

```yaml
- hosts: all
  gather_facts: false            # skip entirely when not needed — big speedup
# or
- hosts: all
  gather_facts: true
  # via module when needed only:
  tasks:
    - ansible.builtin.setup:
        gather_subset: "!all,network"    # only network facts
        filter: "ansible_default_ipv4*"
```

### Custom facts — the forgotten trick

Drop JSON/INI `*.fact` files in `/etc/ansible/facts.d/` on the target; they appear under **`ansible_local`**:

```yaml
- name: Install app version fact
  ansible.builtin.copy:
    content: '{"app_version": "1.8.2", "channel": "stable"}'
    dest: /etc/ansible/facts.d/app.fact
    mode: "0755"
```

Later, any playbook can do: `{{ ansible_facts['ansible_local']['app']['app_version'] }}`.
> 💬 **Say:** *"It turns arbitrary node state into first-class inventory — great for fleet reporting: 'what version is running everywhere?'"*

---

## 4. Magic variables (about the hosts themselves, not their OS)

| Variable | Use |
|---|---|
| `inventory_hostname` | the host's logical inventory name (not DNS) |
| `group_names` | groups this host belongs to |
| `groups` | every group → member list: `{{ groups['web'] }}` |
| `hostvars` | **any host's vars**: `{{ hostvars['web1']['ansible_host'] }}` |
| `ansible_play_batch` / `ansible_play_hosts_all` | hosts in this batch / whole play |
| `ansible_version`, `ansible_config_file` | environment introspection |
| `omit` | special value that **removes a parameter** entirely |

### 🎬 SCENARIO — cross-host data: app servers need the DB endpoint

```yaml
- name: Point app tier at the DB
  hosts: api
  vars:
    db_host: "{{ hostvars[groups['db'][0]].ansible_host }}"   # read another host's facts/vars
    db_replicas: "{{ groups['db'] | map('extract', hostvars, 'ansible_host') | list }}"
  tasks:
    - ansible.builtin.template:
        src: api.conf.j2
        dest: /opt/api/api.conf
```

```jinja
# api.conf.j2
[database]
host = {{ db_host }}
replicas = {{ db_replicas | join(', ') }}
```

> 💬 **Say:** *"Ansible has no global namespace — `hostvars` + `groups` is the sanctioned way to do cross-host references, e.g. generating an nginx upstream list from the `web` group in file 06."*

### The lazy-evaluation gotcha (senior-level detail)

Jinja expressions in values are templated **when used**, not when defined:

```yaml
- hosts: localhost
  vars:
    x: "{{ y }}"
    y: "42"
  tasks:
    - ansible.builtin.debug: { msg: "x = {{ x }}" }   # prints 42!  (y defined after x)
```

That's why recursive templating works and why `import` (parse-time, static) vs `include` (run-time, lazy) behaves differently — file 05.

---

## 5. `set_fact` & registered vars — runtime computation

```yaml
- name: Compute derived values
  ansible.builtin.set_fact:
    is_prod: "{{ 'prod' in group_names }}"
    release_dir: "/opt/{{ app_name }}/{{ app_version }}"
    deploy_ts: "{{ ansible_date_time.iso8601 }}"

- name: Persist across runs (cached fact)
  ansible.builtin.set_fact:
    last_deploy: "{{ ansible_date_time.iso8601 }}"
    cacheable: true          # survives into fact cache — visible to later plays even with gather_facts: false
```

`set_fact` caveats (interview gold):
- It's **host-scoped** and re-evaluated every run (unless `cacheable: true`).
- It outranks nearly everything except `-e` — **never** use it as a config knob; it's for derived values.
- Values are templated immediately at assignment; later var changes don't flow through.

---

## 6. 🎬 SCENARIO — A real multi-env layout (what you'd build at work)

```
├── ansible.cfg
├── site.yml
├── inventories/
│   ├── production/
│   │   ├── hosts.yml
│   │   ├── group_vars/
│   │   │   ├── all.yml          # org-wide: ntp, dns, artifact repo
│   │   │   ├── web.yml
│   │   │   └── vault-enc.yml    # Vault-encrypted secrets (file 09)
│   │   └── host_vars/web1.yml
│   └── staging/ ...
├── group_vars/                  # optional: applies to ALL inventories (repo-wide defaults)
└── roles/
```

```yaml
# inventories/production/group_vars/all.yml
env: production
app_version: "1.8.2"
db_port: 5432

# inventories/staging/group_vars/all.yml
env: staging
app_version: "1.9.0-rc1"      # same playbook, different values
```

```bash
ansible-playbook -i inventories/staging site.yml
ansible-playbook -i inventories/production site.yml
ansible-playbook -i inventories/production site.yml -e "app_version=1.8.3-hotfix"  # emergency override
```

> 💬 **Say:** *"One playbook, N environments, zero `if env == prod` branching inside tasks — env differences live in inventory, not in code. Hotfixes ride `-e`. That's the whole point of the precedence system."*

---

## 7. Debugging variables like a senior

```bash
ansible-inventory -i inventories/production --host web1     # resolved vars for one host
ansible-inventory -i inventories/production --list          # everything
ansible localhost -m debug -a "var=hostvars['web1']" -i inventories/production
ansible-playbook site.yml -e "x=1" --check -v
```

```yaml
- ansible.builtin.debug:
    var: hostvars[inventory_hostname] | dict2items | selectattr('key', 'match', 'app_') | list
```

Precedence crime-scene tip: run with `-vv` and search `TASK [trying different sources]`… or simply bisect with `-e` (winner always).

---

## 8. 🎤 SDE-3 Interview Corner

**Q1. Rank: `-e`, role defaults, `set_fact`, play `vars_files`, task vars.**
> `-e` > set_fact/registered > include_vars > task vars > block vars > role vars > vars_files > play vars > … > role defaults. Exact middle ordering varies by source (role vars sit above play vars_files); anchor points matter more than the middle.

**Q2. `group_vars/all.yml` in the inventory dir AND playbook dir — which wins?**
> Playbook-adjacent beats inventory-adjacent. Rule: closer to your code = stronger (but still weaker than runtime sources).

**Q3. Where should a role's default port live, and how would a consumer override it?**
> `roles/myrole/defaults/main.yml`. Consumers override at any stronger level: group_vars, play vars, or role params `roles: [{role: myrole, vars: {port: 8081}}]`. Never hardcode in role `vars/main.yml` — that's for internal constants you *don't* want overridable.

**Q4. `set_fact` vs registered var?**
> Both land at the same strong tier. `set_fact` = you compute/assign; registered = module hands you a result object. Both die at end of run unless `cacheable: true` (set_fact) — results aren't cached, period.

**Q5. Why do facts sometimes show as `ansible_distribution` and sometimes `ansible_facts['distribution']`?**
> The underscore names are legacy aliases injected for compatibility; `ansible_facts` dict is the modern interface. `ANSIBLE_INJECT_FACT_VARS=False` disables the aliases.

**Q6. How do you share a computed value between hosts in the same run?**
> You don't directly — vars are host-scoped. Patterns: run a task with `run_once` + `set_fact` on every host (loop over `groups['all']` / `delegate_to: item`), or persist to a file/external store and `lookup('file')` it, or use `hostvars` if the value lives on one known host.

---

## ⚠️ Common pitfalls

- Using `set_fact` for config values → invisible overrides that beat group_vars and ruin someone's day.
- YAML type traps: `version: 1.10` is a float (`1.1`)! Quote everything: `version: "1.10"`. Same for `on/off/yes/no` → booleans in YAML 1.1.
- Accessing dict keys with dots after `set_fact` of computed names — use `dict['key']` when keys are dynamic.
- Assuming `hostvars['web1'].x` works for vars only defined in a **later play** — vars materialize per-host as plays execute; order matters.
- `omit` misuse: it only means "drop this parameter", not "empty".

---

**➡️ Next:** [05 — Conditionals, Loops, Tags, Import vs Include](05-control-flow.md)
