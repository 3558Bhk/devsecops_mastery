# 18 — Last-Minute Complete Revision (The Night-Before File)

> ⏱️ **Time:** first pass ~45 min · night before ~30 min · morning of interview ~10 min (⚡ sections only)
> 📦 **Covers:** the entire course compressed — core models, write-from-memory snippets, killer answers, numbers, traps, day-of checklist
> 🎯 **How to use:** full pass 3 days out → mark weak spots → night-before pass on marks → ⚡ sections on the morning

---

## ⚡ PART 0 — The 30-second identity (open with this energy)

> *"Ansible is an **agentless, push-based automation tool**: it SSHes to targets, ships a self-contained Python module, executes it with JSON args, reads back a JSON result (`changed`/`failed`), and cleans up. Playbooks declare **desired end state**; modules diff desired vs actual — that's **idempotency**, which enables safe re-runs, drift detection, and honest reporting."*

Five words to weave into every answer: **idempotency · blast radius · rollback · observability · convergence.**

---

## ⚡ PART 1 — Precedence in 15 seconds (the #1 question)

```
-e (extra vars)  →  set_fact / registered  →  include_vars  →  task vars
→  block vars  →  role vars (vars/)  →  vars_files  →  play vars
→  gathered facts  →  host_vars  →  group_vars  →  inventory vars
→  role defaults (defaults/)  ← weakest
```

Say it as: **"extra always wins; runtime beats static; specific beats general; defaults lose to everything."**

---

## ⚡ PART 2 — Numbers & defaults (rapid recall)

| Fact | Value |
|---|---|
| Default `forks` | 5 (raise to 20–50 for fleets) |
| Default strategy | `linear` (also: `free`, `host_pinned`) |
| `poll: 0` | fire-and-forget async |
| Handler timing | end of play, dedup, changed-only; `meta: flush_handlers` forces mid-play |
| Config file order | `$ANSIBLE_CONFIG` → `./ansible.cfg` → `~/.ansible.cfg` → `/etc/ansible/ansible.cfg` |
| Vault cipher | AES256, PBKDF2 from password |
| pipelining | off by default (legacy `requiretty`); first perf knob |
| Fact cache | `gathering=smart` + jsonfile/redis + TTL |
| `serial: [1, 5, "25%"]` | canary waves — say "canary in one line" |
| `max_fail_percentage: 0` | any failure aborts further waves |
| Inline inventory | `-i "host1,"` — trailing comma! |
| Managed-node req | SSH + Python (`raw`/`script` work without) |
| Jinja `default('x', true)` | also replaces false/empty (plain `default` doesn't) |
| `when` + `loop` | evaluated **per item** |
| import vs include | parse-time/static vs runtime/dynamic (loops OK) |
| Post-reboot | **re-gather facts** before asserting |

---

## PART 3 — Write-from-memory snippets (practice on paper)

### 1. Production `ansible.cfg`
```ini
[defaults]
inventory = ./inventory
forks = 20
gathering = smart
fact_caching = community.general.jsonfile
fact_caching_connection = .fact_cache
[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=300s
```

### 2. Playbook skeleton (shows 6 concepts at once)
```yaml
- name: Deploy
  hosts: web
  become: true
  tasks:
    - name: Render config
      ansible.builtin.template:
        src: app.conf.j2
        dest: /etc/app/app.conf
        validate: "/opt/app/bin/config-check %s"
      notify: Restart app
    - name: Health gate
      ansible.builtin.uri: { url: "http://localhost:8080/healthz", status_code: 200 }
      register: h
      until: h.status == 200
      retries: 5
      delay: 3
      changed_when: false
  handlers:
    - name: Restart app
      ansible.builtin.service: { name: app, state: restarted }
```

### 3. Role tree
```
roles/nginx/{defaults,vars,tasks,handlers,templates,files,meta}/main.yml
```
defaults = overridable knobs (lowest precedence) · vars = internal constants · meta = dependencies.

### 4. block / rescue / always
```yaml
- block:
    - ansible.builtin.import_tasks: deploy.yml
  rescue:
    - ansible.builtin.import_tasks: rollback.yml
  always:
    - ansible.builtin.uri: { url: "http://lb/enable/{{ inventory_hostname }}", method: POST }
```
rescue = on failure (has `ansible_failed_task`) · always = finally · rescue failing = host failed.

### 5. Zero-downtime cycle per host (THE SDE-3 answer)
```yaml
- hosts: web
  serial: [1, 5, "25%"]
  max_fail_percentage: 0
  tasks:
    - { name: drain,   ansible.builtin.uri: { url: "http://lb/drain/{{ inventory_hostname }}", method: POST }, delegate_to: localhost }
    - ansible.builtin.pause: { seconds: 10 }
    - ansible.builtin.import_tasks: deploy_release.yml   # versioned dir + symlink flip + handler restart
    - ansible.builtin.uri: { url: "http://localhost:8080/healthz", status_code: 200 }
    - { name: enable,  ansible.builtin.uri: { url: "http://lb/enable/{{ inventory_hostname }}", method: POST }, delegate_to: localhost }
```
Wrap deploy in block/rescue → **rollback to captured previous release**; `always` re-enables LB.

### 6. Secret-safe template task
```yaml
- ansible.builtin.template:
    src: app.env.j2
    dest: /opt/api/app.env
    mode: "0600"
  no_log: true
  notify: Restart api
```

### 7. Vault commands
```bash
ansible-vault create|edit|view|rekey file.yml
ansible-vault encrypt_string 's3cr3t' --name db_password
ansible-playbook site.yml --vault-id prod@~/.vault-pass-prod
```

---

## PART 4 — Killer scenario blueprints (30-second outlines)

**1. Zero-downtime deploy to 200 hosts** → serial canary waves · drain from LB (`delegate_to`) · wait drained · versioned release + symlink flip · handler restart · health-check gate (`until/retries`) · re-enable · block/rescue rollback · `max_fail_percentage: 0` · CI passes `-e release=…`.

**2. Playbook takes 40 min on 500 hosts** → measure (`profile_tasks`, `timer`) → `pipelining=True` + `ControlPersist` → raise forks → skip/subset/**cache facts** → `strategy: free` / async for slow tasks → `cache_valid_time` on apt → re-measure. (40→8 min story, file 11.)

**3. How do you handle secrets?** → vault-ids per env, `vault_`-prefixed encrypted vars with plaintext indirection, `no_log` on rendering tasks, `chmod 600` password files, and for crown jewels: **external lookups** (Vault/SSM) with TTL + audit. Leaked secret = rotate first, scrub history second.

**4. import vs include** → static parse-time (list-tasks sees children, when/tags stamp all, no loops) vs dynamic runtime (loops, computed names, when once). Default import; include for runtime decisions.

**5. Monthly patching of 400 hosts** → `serial: "10%"`, `package state=latest security=yes`, `reboot` module only `when: patching is changed`, **re-gather facts**, aggregate report via `hostvars` + `run_once`, run from AAP schedule.

**6. DR failover** → human confirmation gate (`vars_prompt`/approval node) → replication-lag check before promote (refuse stale) → reconfig app tier (`validate`) → DNS cutover (TTL 60 set in peacetime) → end-to-end verify through public entrypoint → declare. Failback = reverse, rehearsed.

**7. Where does Ansible fit with Terraform/K8s?** → Terraform provisions/owns lifecycle (state, plan/apply); Ansible configures/orchestrates inside. K8s: GitOps reconciles the cluster; Ansible bootstraps it and runs runbooks/pipeline gates around it.

---

## PART 5 — Top traps (each one is a real interview answer)

1. `shell` everywhere → prefer modules; `changed_when`/`creates` for commands.
2. Handler didn't run → play failed (use `--force-handlers` / `always:`), or `--tags` filtered it.
3. Facts stale **after reboot** → run `setup` again before asserting.
4. `register` + loop → results live in `.results[]`, not `.stdout`.
5. `set_fact` as config knob → beats group_vars invisibly; derived values only.
6. `default('x')` ≠ catch-all → empty string passes; use `default('x', true)` / `mandatory`.
7. Inventory inline list needs trailing comma: `-i "host1,"`.
8. `1.10` unquoted in YAML = float 1.1 — quote versions.
9. Dynamic inventory cache → ghost hosts; filter `instance-state-name=running`, flush before critical runs.
10. `--check` + tasks without check-mode support → skipped or dangerous custom modules (`supports_check_mode`!).
11. `delegate_to` keeps original host's vars; becomes on the delegated target.
12. Rescued ≠ clean: a failed rescue task fails the host — verify your rollback.
13. `no_log` missing on secret-rendering tasks → secrets in job logs.
14. Perpetual `changed` from templates with timestamps/random → deterministic templates.
15. Running full play when you needed 10 hosts → `--limit` + `--list-hosts` first, always.

---

## PART 6 — Vocabulary drops (use precisely, once each)

**AnsiballZ** (module zip) · **converge** (reach declared state) · **desired state vs actual** · **blast radius** (serial/limit) · **canary** (`serial` list) · **drift** (check-mode + scheduled runs catch it) · **EE** (containerized control node, AAP 2.x) · **FQCN** (`ansible.builtin.copy`) · **vault-id** (per-env passwords) · **hostvars/groups** (cross-host data) · **Molecule** (role testing incl. idempotence) · **automation mesh** (execution nodes near hosts).

---

## ⚡ PART 7 — Day-of checklist

**Before:** skim ⚡ sections (10 min) · re-read your two best project stories · water, scratchpad for serial arithmetic.

**Structure every scenario answer:**
1. **Requirements check** (blast radius? rollback? secrets? verification?)
2. **Architecture in one sentence** (waves × per-host cycle)
3. **Mechanisms by name** (serial, delegate_to, block/rescue, validate, handlers, until)
4. **Failure story** (what if health check fails? host dies mid-wave? rollback fails?)
5. **Trade-off named + alternative rejected** (rolling vs blue-green, vault vs external)

**Close with questions:** "Static or dynamic inventory today?" · "Where does Terraform end and Ansible begin?" · "Rolling or GitOps for deploys?" · "Self-service via AAP or CI-driven?"

You've got this. 🚀
