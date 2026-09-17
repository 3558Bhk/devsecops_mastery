# 16 — The Scenario Cookbook: Six End-to-End Projects

> ⏱️ **Time to complete: ~5 hrs** — ~50 min per project (read the design → trace the playbook → rehearse the talking points OUT LOUD)
> 📦 **Covers:** six complete builds — ① LEMP stack orchestrator · ② blue-green cutover · ③ fleet patching with reboots & reporting · ④ hardening baseline · ⑤ user lifecycle (joiner/mover/leaver) · ⑥ DR failover runbook — plus how to present any project as STAR + trade-offs

> **Interview framing:** These are the projects you describe when asked *"Tell me about something you automated."* Each one is a complete design + playbook + talking points. Internalize 2–3 deeply; skim the rest.

**Shared repo layout assumed throughout** (files 02/07 patterns):

```
infra-ansible/
├── ansible.cfg
├── requirements.yml
├── inventories/{production,staging}/
│   ├── hosts.yml
│   ├── group_vars/{all,web,api,db,lb}.yml
│   └── host_vars/
├── site.yml
├── playbooks/
├── roles/{common,nginx,api,postgres,app_deploy,hardening,users}/
└── templates/
```

---

# Project 1 — Full LEMP Stack Deployment (the classic)

> **Prompt:** *"Bring up nginx + PHP-FPM + PostgreSQL app stack across tiers, from zero, repeatably."*

```
        ┌── lb ──┐
users → │ nginx  │ → web tier (nginx+php-fpm) → api tier (gunicorn) → db tier (postgres+replica)
        └────────┘
```

### `site.yml` — the orchestrator (thin on purpose)

```yaml
---
- name: Baseline every host
  ansible.builtin.import_playbook: playbooks/common.yml

- name: Database tier
  ansible.builtin.import_playbook: playbooks/db.yml

- name: Application tier
  ansible.builtin.import_playbook: playbooks/api.yml

- name: Web tier
  ansible.builtin.import_playbook: playbooks/web.yml

- name: Load balancer ( LAST — only routes to verified backends )
  ansible.builtin.import_playbook: playbooks/lb.yml
```

### `playbooks/db.yml` — tier play with ordering guarantees

```yaml
- name: PostgreSQL primary + replica
  hosts: db
  become: true
  tasks:
    - name: Include primary-only tasks
      ansible.builtin.include_tasks: tasks/pg_primary.yml
      when: inventory_hostname == groups['db'][0]

    - name: Configure replicas
      ansible.builtin.include_tasks: tasks/pg_replica.yml
      when: inventory_hostname != groups['db'][0]
```

### `playbooks/web.yml` — the tier everyone sees

```yaml
- name: Web tier (nginx + php-fpm)
  hosts: web
  become: true
  serial: 2                                   # rolling, even on first bring-up
  roles:
    - role: nginx
      vars:
        nginx_vhosts:
          - name: "{{ site_name }}"
            port: 80
            php: true
            upstream: "127.0.0.1:9000"

    - role: php_fpm

  post_tasks:
    - name: Verify each host serves before LB gets it
      ansible.builtin.uri:
        url: "http://localhost/"
        status_code: 200
      register: ok
      until: ok.status == 200
      retries: 5
      delay: 2
```

### `playbooks/lb.yml` — generated from live inventory

```yaml
- name: Load balancer
  hosts: lb
  become: true
  roles:
    - role: nginx
      vars:
        nginx_vhosts:
          - name: "{{ site_name }}"
            port: 80
            upstream: "{{ groups['web'] | map('extract', hostvars, 'ansible_host') | join(', ') }}"
```

**Interview talking points:**
1. **Ordering:** db → api → web → lb. Dependencies come up before consumers; LB last so it only ever routes to configured backends.
2. **Inventory as data:** the LB upstream list is generated from `groups['web']` — add a web host to inventory, re-run, LB updated. Zero template surgery.
3. **`serial: 2` even on first bring-up** — because "bring up a new env" and "update an existing env" must be the same code path (idempotent convergence).
4. Every tier ends with a **verification task** — bring-up proves itself.

---

# Project 2 — Blue-Green Deployment Behind Nginx

> **Prompt:** *"Zero-downtime deploys with instant rollback, at 2× capacity cost."*

```
              ┌─ blue pool: web-b1, web-b2   (live v1.8)
nginx (LB) ───┤
              └─ green pool: web-g1, web-g2  (v1.9 staging)
```

### `playbooks/bluegreen_deploy.yml`

```yaml
- name: Deploy to the INACTIVE color
  hosts: "web_{{ (active_color == 'blue') | ternary('green', 'blue') }}"
  become: true
  tasks:
    - name: Provision new release on inactive color
      ansible.builtin.import_role: { name: app_deploy }

    - name: Full acceptance on inactive color (private health port)
      ansible.builtin.uri:
        url: "http://localhost:8081/healthz?deep=1"
        status_code: 200
      register: deep
      until: deep.status == 200
      retries: 10
      delay: 5

- name: Flip traffic atomically
  hosts: lb[0]
  become: true
  tasks:
    - name: Render LB config pointing at the new color
      ansible.builtin.template:
        src: lb_pool_{{ target_color }}.conf.j2
        dest: /etc/nginx/conf.d/app-pool.conf
        validate: "nginx -t -c %s"
      notify: Reload nginx

    - name: Flush reload NOW (atomic cutover)
      ansible.builtin.meta: flush_handlers

    - name: Canary check through the LB
      ansible.builtin.uri:
        url: "https://{{ site_name }}/healthz"
        status_code: 200
        headers: { X-Canary: "1" }
      register: canary
      until: canary.status == 200
      retries: 5

- name: Keep old color warm for instant rollback
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Record previous color in a fact file for the rollback runbook
      ansible.builtin.copy:
        content: "{{ active_color }}"
        dest: "{{ playbook_dir }}/../.previous_color"
```

**Rollback = re-run the flip play with the old color** (or a `rollback.yml` that reads `.previous_color`). One `nginx -s reload`, zero connection loss.

**Talking points / trade-offs:**
1. **Cutover is one atomic, validated action** (`template` + `validate` + reload) — not 200 host mutations. Blast radius of the *flip* is 1 file.
2. **Deep health check before cutover**, shallow after — acceptance before exposure.
3. **Cost:** 2× fleet. Stateful layers (DB) are shared — schema migrations must be backward-compatible with both colors (expand/contract pattern). Say this; it's the senior trap in blue-green.
4. Rolling (file 10) vs blue-green choice: gradual exposure + less capacity (rolling) vs instant full-fleet validation + instant rollback (blue-green).

---

# Project 3 — Monthly Patching with Controlled Reboots (Linux + Windows)

> **Prompt:** *"Patch 400 servers monthly; reboot only where needed; never take more than 10% down at once; produce a report."*

### `playbooks/patch_linux.yml`

```yaml
- name: Patch Linux fleet
  hosts: all:!lb                    # LBs patched in a dedicated, final wave
  become: true
  serial: "10%"                     # blast radius + failure containment
  any_errors_fatal: false
  max_fail_percentage: 20
  vars:
    security_only: "{{ patch_security_only | default(true) }}"

  tasks:
    - name: Snapshot current kernel for the report
      ansible.builtin.command: uname -r
      register: kernel_before
      changed_when: false

    - name: Apply updates (security only by default)
      ansible.builtin.package:
        name: "*"
        state: latest
        security: "{{ security_only if ansible_facts['pkg_mgr'] == 'apt' else omit }}"
      register: patching
      environment:
        DEBIAN_FRONTEND: noninteractive

    - name: Reboot only if the patch run demands it
      ansible.builtin.reboot:
        reboot_timeout: 900
        pre_reboot_delay: 10
        test_command: "systemctl is-system-running || true"
      when: patching is changed
      register: rebooted

    - name: Re-gather facts (post-reboot truth!)
      ansible.builtin.setup: { filter: ansible_kernel }
      when: rebooted is changed

    - name: Record what happened on THIS host
      ansible.builtin.set_fact:
        patch_result:
          host: "{{ inventory_hostname }}"
          old_kernel: "{{ kernel_before.stdout }}"
          new_kernel: "{{ ansible_facts['kernel'] }}"
          rebooted: "{{ rebooted is changed }}"

- name: Fleet report (runs once, aggregates everything)
  hosts: all:!lb
  gather_facts: false
  tasks:
    - name: Build the report (control node)
      ansible.builtin.copy:
        content: |
          Host          Old → New Kernel                Rebooted
          {% for h in ansible_play_hosts_all %}
          {{ "%-14s" | format(h) }} {{ hostvars[h].patch_result.old_kernel }} → {{ hostvars[h].patch_result.new_kernel }}  {{ hostvars[h].patch_result.rebooted }}
          {% endfor %}
        dest: "/var/reports/patch-{{ lookup('pipe', 'date +%F') }}.txt"
      delegate_to: localhost
      run_once: true

    - name: Slack summary
      ansible.builtin.uri:
        url: "{{ slack_webhook }}"
        method: POST
        body_format: json
        body:
          text: "Patch run complete: {{ ansible_play_hosts_all | length }} hosts, report attached."
      delegate_to: localhost
      run_once: true
```

### Windows variant (know it exists — `win_updates`)

```yaml
- name: Patch Windows fleet
  hosts: windows
  serial: "10%"
  tasks:
    - name: Install OS updates
      ansible.windows.win_updates:
        category_names: [SecurityUpdates, CriticalUpdates]
        reboot: true                    # win_updates handles the reboot dance
        reboot_timeout: 1800
      register: wu
    - ansible.builtin.debug:
        msg: "installed={{ wu.found_update_count }} reboot={{ wu.reboot_required }}"
```

**Talking points:**
1. **`serial: "10%"` + `max_fail_percentage`** — bounded blast radius; a bad patch halts waves at 20% failure, not 100%.
2. **`reboot` module** — handles init, disconnect, wait, reconnect; then **re-gather facts** (the post-reboot stale-fact trap from file 10).
3. **Report aggregates via `hostvars` + `ansible_play_hosts_all`** in a final `run_once` play — because vars are host-scoped (file 04).
4. In real life this runs from **AAP schedules** (file 15) with maintenance windows per group — not a human typing a command.

---

# Project 4 — Server Hardening Baseline (CIS-lite)

> **Prompt:** *"Every new VM must meet our security baseline. Enforce it continuously."*

### `roles/hardening/tasks/main.yml` (excerpted — the interview-worthy parts)

```yaml
- name: SSH hardening
  ansible.builtin.template:
    src: sshd_hardened.conf.j2
    dest: /etc/ssh/sshd_config.d/50-hardening.conf
    mode: "0600"
    validate: "/usr/sbin/sshd -t -f %s"      # never brick SSH access
  notify: Restart sshd

- name: Password quality
  community.general.ini_file:
    path: /etc/security/pwquality.conf
    section: ""
    option: "{{ item.key }}"
    value: "{{ item.value }}"
  loop: "{{ pwquality | dict2items }}"

- name: Firewall default deny + allowlist
  community.general.ufw:
    state: enabled
    policy: deny
    logging: "on"

- name: Allow only inventory-declared ports
  community.general.ufw:
    rule: allow
    port: "{{ item }}"
    proto: tcp
  loop: "{{ open_ports | default([22]) }}"
  loop_control: { label: "port {{ item }}" }

- name: Fail2ban present and enabled
  ansible.builtin.package: { name: fail2ban, state: present }
  ansible.builtin.service: { name: fail2ban, state: started, enabled: true }

- name: Auditd for the forensics trail
  ansible.builtin.package: { name: auditd, state: present }

- name: Kernel sysctls
  ansible.posix.sysctl:
    name: "{{ item.name }}"
    value: "{{ item.value }}"
    sysctl_set: true
    reload: true
  loop:
    - { name: net.ipv4.conf.all.rp_filter,      value: "1" }
    - { name: net.ipv4.tcp_syncookies,          value: "1" }
    - { name: kernel.randomize_va_space,        value: "2" }
    - { name: fs.protected_symlinks,            value: "1" }

- name: Verify baseline (the play fails if we're NOT hardened)
  block:
    - ansible.builtin.command: sshd -T
      register: sshd_effective
      changed_when: false
    - ansible.builtin.assert:
        that:
          - "'permitrootlogin no' in sshd_effective.stdout"
          - "'passwordauthentication no' in sshd_effective.stdout"
        success_msg: "Baseline verified"
```

**Talking points:**
1. **`validate` on sshd config** — the single scariest remote-config mistake is bricking SSH; a syntax check before write prevents it. Same discipline as sudoers in file 02.
2. **Declarative allowlist** (`open_ports` from `group_vars/<tier>.yml`) — the firewall is data-driven from inventory: a new service declares its port, hardening doesn't need editing.
3. **Self-verifying play** — the final `assert` against `sshd -T` (effective config, not file contents) makes the play a **compliance gate**; wire it to run nightly or on AAP schedule and drift gets caught, not assumed.
4. Firewall before services → during bring-up the baseline is applied before app ports open.

---

# Project 5 — User Lifecycle (Joiners / Movers / Leavers)

> **Prompt:** *"Onboard, move between teams, and offboard engineers across 200 servers — from a single source of truth."*

### Source of truth: `group_vars/all/users.yml` (or a CMDB lookup)

```yaml
users:
  alice: { uid: 2101, groups: [dev, platform], key: "ssh-ed25519 AAAA... alice@laptop", state: present }
  bob:   { uid: 2102, groups: [dev],           key: "ssh-ed25519 AAAB... bob@laptop",   state: present }
  carol: { uid: 2103, groups: [],              key: "",                                 state: absent }  # leaver
```

### `playbooks/users.yml`

```yaml
- name: Manage engineer access
  hosts: all
  become: true
  tasks:
    - name: Ensure groups exist
      ansible.builtin.group:
        name: "{{ item }}"
        state: present
      loop: "{{ users.values() | map(attribute='groups') | flatten | unique | select | list }}"

    - name: Create / remove accounts (state drives everything)
      ansible.builtin.user:
        name: "{{ item.key }}"
        uid: "{{ item.value.uid }}"
        groups: "{{ (item.value.groups | default([])) | join(',') }}"
        shell: /bin/bash
        state: "{{ item.value.state }}"
        remove: true                          # leaver: delete home dir too
      loop: "{{ users | dict2items }}"
      loop_control: { label: "{{ item.key }} ({{ item.value.state }})" }

    - name: Sync SSH keys (exclusive = remove ALL others — desired state)
      ansible.posix.authorized_key:
        user: "{{ item.key }}"
        key: "{{ item.value.key }}"
        state: present
        exclusive: true
      loop: "{{ users | dict2items | selectattr('value.state', '==', 'present') | list }}"
      when: item.value.key | length > 0

    - name: Leaver hygiene — kill sessions & cron
      ansible.builtin.command: pkill -u {{ item.key }}
      loop: "{{ users | dict2items | selectattr('value.state', '==', 'absent') | list }}"
      failed_when: false
      changed_when: true
      when: item.value.groups | default([]) | length == 0
```

**Talking points:**
1. **`state: absent` + `remove: true`** — offboarding is not a delete script; it's declarative desired state, idempotent forever.
2. **`exclusive: true` on authorized_key** — removes keys that aren't in the source of truth (stale laptop keys are a classic audit finding). With a caveat to mention: it also removes emergency/break-glass keys, so those live under a separate managed marker file via `blockinfile`.
3. Source of truth in **git = reviewed, audited changes** (MR approves access); or a CMDB `lookup`. Either way: *one* file, *N* hosts.
4. `loop_control.label` keeps logs human-scannable across 200 hosts × N users.

---

# Project 6 — Disaster Recovery Runbook (automated failover)

> **Prompt:** *"Primary region is down. You have warm standbys in region B. Automate the failover."* (This one is about **orchestration under pressure** — the purest SDE-3 scenario.)

### `playbooks/dr_failover.yml`

```yaml
- name: DR FAILOVER — run only after human confirmation
  hosts: localhost
  connection: local
  gather_facts: false
  vars_prompt:
    - name: confirm
      prompt: "This will promote DR and redirect traffic. Type FAILOVER to proceed"
      private: false
  pre_tasks:
    - name: Hard confirmation gate
      ansible.builtin.assert:
        that: confirm == "FAILOVER"
        fail_msg: "Aborted — confirmation mismatch"

- name: 1. Promote database replica to primary
  hosts: db_dr[0]
  become: true
  tasks:
    - name: Check replication lag before promoting (stale data = lost writes)
      ansible.builtin.command: psql -Atc "SELECT COALESCE(EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp()),0)"
      register: lag
      changed_when: false
    - ansible.builtin.assert:
        that: lag.stdout | float < 60
        fail_msg: "Replica lag {{ lag.stdout }}s > 60s — escalate, do not promote"

    - name: Promote
      ansible.builtin.command: pg_ctlcluster 15 main promote
      register: promote
      changed_when: promote.rc == 0

- name: 2. Bring app tier up against DR
  hosts: app_dr
  become: true
  serial: 100%                    # DR: speed over rolling caution; config-only change
  tasks:
    - name: Point apps at promoted primary
      ansible.builtin.template:
        src: app.conf.j2
        dest: /opt/app/app.conf
        validate: "/opt/app/bin/config-check %s"
      notify: Restart app
      vars:
        db_host: "{{ hostvars[groups['db_dr'][0]].ansible_host }}"
    - ansible.builtin.meta: flush_handlers
    - ansible.builtin.uri: { url: "http://localhost:8080/healthz", status_code: 200 }

- name: 3. Redirect DNS (traffic cutover)
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Lower TTL record to DR load balancer
      community.aws.route53:
        state: present
        zone: example.com
        record: app.example.com
        type: A
        value: "{{ groups['lb_dr'] | map('extract', hostvars, 'ansible_host') | list }}"
        overwrite: true
        ttl: 60                      # low TTL ONLY exists because we set it up in peacetime

- name: 4. Verify & declare
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: End-to-end check through public entrypoint
      ansible.builtin.uri:
        url: "https://app.example.com/healthz"
        status_code: 200
      register: e2e
      until: e2e.status == 200
      retries: 10
      delay: 30
    - name: Notify incident channel
      ansible.builtin.uri:
        url: "{{ slack_webhook }}"
        method: POST
        body_format: json
        body: { text: "✅ FAILOVER COMPLETE — app.example.com serving from region B" }
```

**Talking points (this project is 80% talking points):**
1. **Human confirmation gate** (`vars_prompt` + `assert`) — DR automation runs rarely and must not run by accident; in AAP this is an **approval node**.
2. **Lag check before promote** — the #1 DR mistake is promoting a stale replica and silently losing writes. The automation *refuses* to do the unsafe thing.
3. **`ttl: 60` exists in peacetime** — DNS failover is only as fast as the TTL you set months earlier. DR is 90% preparation.
4. **Config-only app changes in DR** (`serial: 100%`) — no rolling caution needed when hosts are already running; the risk is config, applied atomically.
5. **End-to-end verification through the public entrypoint** — "the runbook doesn't end when the last task passes; it ends when a user-visible check passes."
6. Practice the inverse too: **failback** (reverse replication, then switch back) — interviewers probe whether you've thought past the hero moment.

---

# 🎤 How to present projects in interviews (the meta-skill)

For every project, structure the story as **STAR + trade-offs**:

1. **Situation/Scale:** "400 hosts, 3 envs, 40 engineers needed self-service."
2. **Task/Constraint:** "Zero downtime, audited, no SSH for devs."
3. **Action:** name the *mechanisms* — serial waves, block/rescue rollback, hostvars aggregation, validate+handlers, dynamic inventory.
4. **Result:** numbers — "deploys from 2h manual to 6min automated; failed-change rate near zero; on-call pages down 70%."
5. **Trade-off discussion:** rolling vs blue-green cost; Vault vs external secrets; static vs dynamic inventory; what you'd do differently.

That last point is what actually makes it SDE-3: **you can defend the choice you made and name the alternative you rejected.**

---

**➡️ Next:** [17 — Interview Cheat Sheet (rapid-fire revision)](17-interview-cheatsheet.md)
