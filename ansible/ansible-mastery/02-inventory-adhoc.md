# 02 — Inventory & Ad-hoc Commands (Targeting at Scale)

> ⏱️ **Time to complete: ~1.5 hrs** — read 20 min · practice 60 min · self-quiz 10 min
> 📦 **Covers:** INI vs YAML inventories · groups & groups-of-groups · behavior host vars (ansible_host, ProxyJump) · targeting patterns & `--limit` · the production directory layout (group_vars/host_vars) · ad-hoc commands · command vs shell vs raw vs script · the bootstrap scenario · dynamic inventory intro

> **Interview framing:** Inventory is how you think about your fleet. SDE-3 questions here are about *structure at scale* — multi-env layouts, group-of-groups, patterns, and the jump to dynamic inventory.

---

## 1. The two formats

### INI (fine for small setups)

```ini
# inventory/production
[web]
web1 ansible_host=10.0.1.11 ansible_user=deploy
web2 ansible_host=10.0.1.12
web3 ansible_host=10.0.1.13

[db]
db1 ansible_host=10.0.2.11

[web:children]        # group of groups
canary
stable

[canary]
web1

[stable]
web2
web3

[prod:children]       # top-level env group
web
db

[prod:vars]
ansible_user=deploy
```

### YAML (better for big fleets)

```yaml
# inventory/production.yml
all:
  children:
    prod:
      children:
        web:
          hosts:
            web1: { ansible_host: 10.0.1.11 }
            web2: { ansible_host: 10.0.1.12 }
            web3: { ansible_host: 10.0.1.13 }
        db:
          hosts:
            db1: { ansible_host: 10.0.2.11 }
      vars:
        ansible_user: deploy
    canary:
      hosts:
        web1:
```

Ranges save typing: `web[1:50]`, `db-[a:f].example.com`.

### The directory convention (MEMORIZE — it's the standard layout)

```
inventory/
├── production/
│   ├── hosts.yml              # hosts & groups only
│   ├── group_vars/
│   │   ├── all.yml            # every host
│   │   ├── web.yml            # every web host
│   │   └── db.yml
│   └── host_vars/
│       └── web1.yml
└── staging/
    ├── hosts.yml
    ├── group_vars/
    └── host_vars/
```

`group_vars/web.yml` automatically applies to hosts in group `web`. No `:vars` sections needed. This is the layout every production repo uses.

---

## 2. Host variables that change Ansible's behavior

| Variable | Purpose |
|---|---|
| `ansible_host` | Real IP/hostname to connect to (logical name ≠ DNS name) |
| `ansible_port` | SSH port |
| `ansible_user` | SSH user |
| `ansible_ssh_private_key_file` | key path |
| `ansible_connection` | `ssh` (default), `local`, `docker`, `winrm`, `network_cli` |
| `ansible_become` / `ansible_become_pass` | privilege escalation |
| `ansible_ssh_common_args` | e.g. `-o ProxyJump=bastion.example.com` for bastion-only networks |

```ini
[bastioned]
web1 ansible_host=10.0.1.11 ansible_ssh_common_args='-o ProxyJump=deploy@bastion'
```

> 💬 Interview: *"How do you reach private-subnet hosts?"* → ProxyJump in `ansible_ssh_common_args`, or an `ssh_config` block, or run from a bastion with `delegate_to`.

---

## 3. Targeting patterns (they WILL ask you to write one live)

```
ansible-playbook -i inventory site.yml -l <pattern>

all  (or *)
web                      one group
web:db                   union        (web OR db)
web:&prod                intersection (web AND prod)
web:!canary              exclusion    (web except canary)
web1:web5                union of hosts
~(web|db)\d+\.prod\.com  regex
web[0]                   first member of the group
web[-1]                  last member
```

### 🎬 SCENARIO — "Deploy to prod web tier, but never the canary, tonight."

```bash
ansible-playbook -i inventory/production site.yml \
  --limit 'web:!canary' \
  --extra-vars "release=v2.4.1"
```

With `serial: 2` in the play (file 10), that's a controlled rollout excluding the canary host. This one-liner is a very common whiteboard question.

### Inspecting inventory like a senior

```bash
ansible-inventory -i inventory/production --list     # full JSON: hosts, groups, vars
ansible-inventory -i inventory/production --graph    # tree view
ansible-inventory -i inventory/production --host web1
ansible-playbook site.yml --list-hosts               # who would be affected? ALWAYS check first
```

> **Senior signal:** *"I never run a playbook without `--list-hosts` first. Blast radius comes before the run."*

---

## 4. Ad-hoc commands — when a playbook is overkill

```bash
ansible all -m ping                                        # connectivity
ansible web -m service -a "name=nginx state=restarted" -b # emergency restart
ansible web -m command -a "df -h /"                        # no shell features, safe
ansible web -m shell -a "free -m | grep Mem"               # pipes needed
ansible web -m copy -a "src=/tmp/fix.conf dest=/etc/app/" -b
ansible web -m apt -a "name=curl state=present" -b
ansible all -m setup -a "filter=*ipv4*"                    # facts
ansible all -m command -a "uptime" -o                      # -o = one line per host
```

**`command` vs `shell` vs `raw` vs `script`** (classic 4-way question):

| Module | Shell features? | Python on target? | Idempotent? | Use when |
|---|---|---|---|---|
| `command` | ❌ (args passed directly to exec) | ✅ | n/a (always changed) | default; safe, no injection |
| `shell` | ✅ (`|`, `>`, `$VAR`, globs) | ✅ | no | only when piping needed; lint warns |
| `raw` | ✅ | ❌ **no Python needed** | no | bootstrapping Python, network gear |
| `script` | runs a local script on target | ❌ | no | drop-in bash migration |

Golden rules: **prefer `command`**, add `creates:`/`removes:` to make it conditional, and in CI use `ansible-lint` rule `command-instead-of-shell` to catch abuses.

---

## 5. 🎬 SCENARIO — Onboarding new servers (chicken-and-egg)

> *"New VMs only have root SSH. You want to manage them as an unprivileged `deploy` user with key auth. How?"*

Two-phase bootstrap:

```yaml
# bootstrap.yml  — phase 1 runs as root, phase 2 never touches root again
- name: Phase 1 — create deploy user (as root, one last time)
  hosts: new_nodes
  become: true
  vars:
    deploy_user: deploy
  tasks:
    - name: Create group + user
      ansible.builtin.group: { name: "{{ deploy_user }}", state: present }
    - ansible.builtin.user:
        name: "{{ deploy_user }}"
        groups: ["{{ deploy_user }}", "sudo"]
        shell: /bin/bash
        create_home: true

    - name: Install public key
      ansible.posix.authorized_key:
        user: "{{ deploy_user }}"
        key: "{{ lookup('file', '~/.ssh/id_ed25519.pub') }}"
        exclusive: true          # remove stale keys — desired-state thinking

    - name: Allow passwordless sudo for deploy
      ansible.builtin.copy:
        content: "{{ deploy_user }} ALL=(ALL) NOPASSWD:ALL\n"
        dest: "/etc/sudoers.d/{{ deploy_user }}"
        mode: "0440"
        validate: "visudo -cf %s"     # never corrupt sudoers!

- name: Phase 2 — verify as deploy
  hosts: new_nodes
  tasks:
    - ansible.builtin.ping
```

Then: inventory sets `ansible_user=deploy` permanently, and a **hardening play** (file 16, project 4) disables root SSH. The `validate:` on sudoers is a great detail to mention — a broken sudoers file can lock you out of a fleet.

---

## 6. Static → Dynamic: the one-liner interview answer

> *"Static inventory is a file I maintain. Dynamic inventory is an **inventory plugin** (or script) that queries a source of truth — AWS, Azure, GCP, vCenter, CMDB, even a JSON endpoint — at run time, so the fleet is never stale. Since 2.10+, plugins are preferred over executable scripts; both output standardized host/group data. I cache it (`cache: true` + a fact-cache plugin) so 5,000 EC2 describe-calls don't slow every run."*

Deep dive with full `aws_ec2` config → **file 12**.

---

## 7. 🎤 SDE-3 Interview Corner

**Q1. You manage 3,000 hosts across 4 envs. Design your inventory.**
> Repo layout: `inventories/<env>/` with `hosts.yml` + `group_vars/` + `host_vars/`. Cloud hosts come from **dynamic inventory plugins** merged with static entries for bare metal (multiple `-i` sources). Groups mirror org structure: env → tier (`web/api/db`) → region → role (canary/primary). Env-wide defaults in `group_vars/all.yml`, overridden per tier. Secrets live in Vault-encrypted `group_vars/<env>.yml`. Anything host-specific (IPs) belongs in host_vars or comes from the cloud API — never hand-maintained.

**Q2. Difference between vars defined in the inventory file `[web:vars]` vs `group_vars/web.yml`?**
> Semantically identical, different precedence: `[web:vars]` (parsed inventory) sits slightly **higher** than `group_vars/` (inventory plugin dirs) — and playbook-adjacent `group_vars/` sits higher than inventory-adjacent ones. In practice: use directory form for maintainability; know that `-e` beats everything anyway.

**Q3. How do you prevent accidental prod runs?**
> Separate inventory dirs, `--list-hosts` habit, canary groups + `serial`, and at platform level (AWX) RBAC + approval workflow gates. Also useful: a `prod` group var like `confirm: yes` and a `failed_when: confirm|default('no') != 'yes'` pre-task guard on destructive plays.

**Q4. A host is in two groups with conflicting vars — what wins?**
> The **more specific** definition generally wins for scalar merge (host_vars > group_vars; child group > parent). Dicts follow `hash_behaviour` (default `replace` — last definition wins wholesale; most orgs keep the default and use `combine` filter explicitly instead of relying on merge).

---

## ⚠️ Common pitfalls

- `ansible all -i "node1," -m ping` — forgetting the **trailing comma** in inline host lists.
- Putting passwords in inventory files (plaintext, committed) → Vault-encrypted `group_vars/`.
- Regex patterns need `~` prefix: `-l "~web\d+"`.
- `:children` in INI creates a group **of groups** — but a host listed there directly is an error-ish trap; use `:vars` for group vars, not `:children`.
- Duplicate host in multiple groups is fine (it's one host, vars merge by precedence) — but duplicate **host keys in YAML** silently overwrite.

---

**➡️ Next:** [03 — Playbook Fundamentals](03-playbook-basics.md)
