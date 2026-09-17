# 01 — Fundamentals & Architecture (How Ansible Actually Works)

> ⏱️ **Time to complete: ~2.5 hrs** — read 30 min · lab practice 90 min · self-quiz 30 min
> 📦 **Covers:** what Ansible is & the agentless push model · how a module actually executes over SSH (AnsiballZ) · idempotency & the meaning of `changed` · installation & ansible-core vs ansible · ansible.cfg + config precedence · facts · ad-hoc commands · first playbook with handlers · declarative vs procedural

> **Interview framing:** Before any playbook question, interviewers check whether you understand *what Ansible is* and *how it executes*. Get this right and everything else makes sense.

---

## 1. What Ansible is (the 30-second answer you should give)

> *"Ansible is an **agentless, push-based IT automation tool** written in Python. It automates configuration management, application deployment, and orchestration by SSH-ing into hosts, shipping small self-contained **modules** (Python scripts) to them, executing them with JSON arguments, reading back a JSON result, and deleting itself. Playbooks describe a **desired end state declaratively**, and Ansible figures out the diff — which is what makes it idempotent."*

Memorize that. It answers "What is Ansible?", "How does it work internally?", and "Why agentless?" in one breath.

### The mental model

```
CONTROL NODE                        MANAGED NODES (no agent!)
┌─────────────────────┐   SSH       ┌──────────────────────┐
│ ansible-playbook     │ ──────────▶│ /tmp/ansible-tmp-xyz │
│  ├── your YAML       │  1. conn   │  ├── AnsiballZ pkg   │
│  ├── inventory       │  2. upload │  ├── module.py       │
│  ├── roles/          │  3. exec   │  └── (Python 3)      │
│  └── ansible.cfg     │ ◀──────────│  JSON result:        │
│                      │  4. result │  {changed, failed…}  │
└─────────────────────┘  5. cleanup └──────────────────────┘
```

Execution of ONE task on ONE host:
1. Control node builds a self-extracting zip of the module ("AnsiballZ").
2. Opens/reuses an SSH connection, creates a temp dir, uploads via SFTP.
3. Executes `python module_zip <JSON args>`.
4. Module performs **state comparison** (is the package already installed? is the file content already correct?), does work only if needed, prints JSON: `{"changed": true/false, "failed": false, ...}`.
5. Deletes the temp dir.

Only requirement on managed nodes: **Python** (and SSH). For devices/legacy boxes without Python there's the `raw` module.

---

## 2. The vocabulary (interviewers test definitions)

| Term | Meaning |
|---|---|
| **Control node** | Machine where Ansible is installed; runs playbooks. Only Linux/macOS officially (Windows via WSL). |
| **Managed node / host** | Server being automated. No agent, no Ansible install needed. |
| **Inventory** | List of hosts + groups + per-host/group variables. |
| **Module** | Unit of work (`apt`, `copy`, `template`…). ~3000+ across collections. Idempotent by design. |
| **Task** | One module invocation with arguments. |
| **Play** | An ordered set of tasks mapped to a set of hosts. |
| **Playbook** | YAML file containing one or more plays. |
| **Handler** | Task triggered by `notify`, runs **once at end of play** if notified (e.g., restart service). |
| **Role** | Reusable, structured bundle of tasks/vars/templates/handlers. |
| **Collection** | Packaged distribution format for modules/plugins/roles (namespace.collection). |
| **Idempotency** | Running the same task twice = same result; second run reports `ok`, not `changed`. |
| **Facts** | Discovered host data (OS, IPs, memory…) gathered by the `setup` module. |

---

## 3. Installation & tooling

```bash
# Modern install: pip in a venv (what you should say in an interview)
python3 -m venv .venv && source .venv/bin/activate
pip install ansible            # ansible-core + ~90 blessed community collections
pip install ansible-core       # engine only, if you want zero bloat

ansible --version              # shows core version, config file, python version
ansible-doc -l | wc -l         # list modules
ansible-doc copy -s            # short snippet of a module's args
```

**`ansible` vs `ansible-core`** (asked surprisingly often):
- `ansible-core` — the engine: CLI, base plugins, `ansible.builtin` modules only.
- `ansible` — the community package: core + popular collections (`community.general`, `ansible.posix`, `amazon.aws`, `kubernetes.core`…) pre-installed.
- Anything else: `ansible-galaxy collection install community.docker`.

**Config file resolution order** (first found wins — classic question):

```
1. $ANSIBLE_CONFIG env var
2. ./ansible.cfg            (per-project — best practice, commit it)
3. ~/.ansible.cfg
4. /etc/ansible/ansible.cfg (system default)
ansible --version  →  shows which one is active
```

A production-grade `ansible.cfg`:

```ini
[defaults]
inventory            = ./inventory
remote_user          = deploy
private_key_file     = ~/.ssh/id_ed25519
host_key_checking    = False        # True in prod with pre-shared known_hosts!
forks                = 20           # parallel hosts (default 5)
gathering            = smart        # cache facts instead of re-gathering
fact_caching         = jsonfile
fact_caching_connection = .fact_cache
fact_caching_timeout = 86400
retry_files_enabled  = False
stdout_callback      = community.general.yaml   # readable output
callbacks_enabled    = profile_tasks, timer     # slow-task profiling
interpreter_python   = auto_silent
deprecation_warnings = True

[ssh_connection]
pipelining           = True         # HUGE speed win, see file 11
ssh_args             = -o ControlMaster=auto -o ControlPersist=120s
```

---

## 4. 🎬 SCENARIO 1 — "Day 0: you've been handed 3 fresh servers"

> *Interview prompt: "You have root SSH to `node1..3`. Bring them to a managed state and prove Ansible works."*

### Step 1 — inventory + first contact

```bash
# inventory (INI form for now)
echo -e "[web]\nnode1\nnode2\n[db]\nnode3" > inventory
```

```bash
ansible web -i inventory -m ping -u root
```

```text
node1 | SUCCESS => { "changed": false, "ping": "pong" }
node2 | SUCCESS => { "changed": false, "ping": "pong" }
```

> 💬 **Say in interview:** the `ping` module doesn't ping ICMP — it logs in over SSH, runs the tiny Python module, and confirms the whole pipeline (auth, Python, transfer) works. `changed: false` proves idempotency — nothing was mutated.

### Step 2 — what do I even have? (facts)

```bash
ansible web -i inventory -m setup -a "filter=ansible_distribution*"
```

Returns `ansible_distribution: Ubuntu`, version, etc. Facts drive 80% of conditional logic later.

### Step 3 — mutate state with an ad-hoc command

```bash
ansible web -i inventory -m ansible.builtin.apt -a "name=nginx state=present update_cache=yes" -b
ansible web -i inventory -m ansible.builtin.service -a "name=nginx state=started enabled=yes" -b
```

Run the first command **again**:

```text
node1 | SUCCESS => { "changed": false, ... }   ← idempotent: already installed
```

> 💬 **Say in interview:** *"I always re-run a command to verify idempotency. `command`/`shell` modules are the exception — they always report `changed`, because Ansible can't know the effect; that's why production playbooks prefer real modules or wrap shell with `changed_when`/`creates`."*

### Step 4 — verify the actual outcome, not just the module result

```bash
ansible web -i inventory -m uri -a "url=http://localhost status_code=200" -b
```

> **Senior signal:** "I don't trust `changed: false` as proof of correctness — I verify behavior with `uri`, `wait_for`, or smoke-test tasks."

---

## 5. 🎬 SCENARIO 2 — your first real playbook (same goal, repeatable)

Ad-hoc = one-off. Playbook = **the same operation, versioned and repeatable**.

```yaml
# site.yml — bootstrap nginx on the web tier
- name: Configure nginx webservers
  hosts: web
  become: true                      # sudo to root on the targets

  tasks:
    - name: Install nginx
      ansible.builtin.apt:
        name: nginx
        state: present
        update_cache: true

    - name: Deploy homepage
      ansible.builtin.copy:
        content: "Served by {{ inventory_hostname }}\n"
        dest: /var/www/html/index.html
        mode: "0644"
      notify: Reload nginx          # only fires if the file CHANGED

    - name: Ensure nginx is running and enabled
      ansible.builtin.service:
        name: nginx
        state: started
        enabled: true

    - name: Smoke test
      ansible.builtin.uri:
        url: "http://localhost/"
        status_code: 200
      register: smoke
      changed_when: false           # a GET never "changes" anything

  handlers:
    - name: Reload nginx
      ansible.builtin.service:
        name: nginx
        state: reloaded
```

```bash
ansible-playbook -i inventory site.yml
```

Three concepts hidden in these 30 lines that interviewers drill:

1. **`become`** — privilege escalation via sudo; the password is only on the control node.
2. **`notify` → handler** — the restart happens **at most once per play**, and only if at least one notifying task actually changed something. 50 `copy` changes = 1 reload, not 50.
3. **`changed_when: false`** — teaching Ansible about your command's semantics so re-runs stay clean.

### Safety workflow you should narrate

```bash
ansible-playbook -i inventory site.yml --syntax-check   # parse only
ansible-playbook -i inventory site.yml --check --diff   # dry-run + show diffs
ansible-playbook -i inventory site.yml --limit node1    # blast radius: 1 host first
ansible-playbook -i inventory site.yml                  # full run
```

---

## 6. Declarative vs procedural — THE defining property

**Procedural (bash):** `apt-get install nginx; service nginx start` — re-running is wasteful or breaks.
**Declarative (Ansible):** *ensure nginx is present and running.* If it already is → no-op.

Interview extension: **"Is Ansible fully declarative?"** Smart answer:

> *"Mostly. Modules like `apt` are declarative — they diff desired vs actual state. But the playbook **execution order is procedural** (top to bottom), and `command`/`shell` tasks are imperative escape hatches. Terraform is declarative with a full state file and plan/apply; Ansible diffs state **live on the target**, which is why it needs no state file — and also why it can't destroy-then-recreate resources the way Terraform does."*

---

## 7. 🎤 SDE-3 Interview Corner

**Q1. Why is Ansible agentless, and what are the trade-offs?**
> Push over SSH; nothing to install/upgrade on targets, works with any SSH-reachable box, low attack surface (temp modules are removed). Trade-offs: control node is a SPOF-ish chokepoint (scale via `forks`, or AAP execution nodes), needs Python on targets, no continuous reconciliation (it's not a daemon — unlike Chef/Puppet clients that pull and self-heal every N minutes). If you need pull-based self-healing with Ansible, you run it from cron/systemd timer on the node (`ansible-pull`) or via AWX schedules.

**Q2. How does a module actually execute?**
> AnsiballZ zip → temp dir over SFTP → `python` subprocess with JSON args → prints JSON → cleanup. `changed` is computed inside the module by comparing state. You can see it live with `-vvv`.

**Q3. What does `changed` really mean?**
> "The module mutated the system." Not "the task ran". That's why `command` tasks pollute reports (always changed) and why you fix them with `changed_when`/`creates`. Dashboards and CI gates key off changed counts — treat false `changed` as a bug.

**Q4. Ansible vs shell scripts for automation?**
> Idempotency, error handling per task, parallelism (`forks`), inventory targeting, variables/facts, secrets (Vault), audit trail (output logs), ecosystem of 3k+ tested modules vs hand-rolled `if grep` checks.

**Q5. Ansible vs Puppet/Chef/Salt?**
> Agentless push (vs agent pull), YAML over Ruby DSL, no master/state server required, procedural-ish ordering. Trade-off: Puppet keeps nodes converged continuously; Ansible converges only when you push.

**Q6. What languages does Ansible require where?**
> Control node: Python 3.x + ansible package. Managed: Python (3.x typical) for most modules; `raw`/`script` modules work without Python (bootstrap scenario: use `raw` to install Python first).

**Q7. Where does the SSH key live / how do you onboard 50 new hosts with no shared credentials?**
> `authorized_key` module to install a deploy user's pubkey via a one-time bootstrap (root or cloud-init), then lock root login — that's file 03's scenario.

---

## ⚠️ Common pitfalls (say you've seen these)

- Editing `/etc/ansible/ansible.cfg` and wondering why nothing changed → a local `./ansible.cfg` is shadowing it (`ansible --version` shows the active one).
- Forgetting `become: true` → tasks fail with permission errors on system paths.
- Using `-m ping` to mean network ping — it's an auth/Python sanity check.
- Leaving `host_key_checking = False` in prod → MITM risk; pre-seed `known_hosts` instead.
- Assuming order doesn't matter — plays run in file order, tasks strictly in order, hosts in parallel chunks of `forks`.

---

**➡️ Next:** [02 — Inventory & Ad-hoc Commands](02-inventory-adhoc.md)
