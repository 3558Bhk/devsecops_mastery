# 00 — How to Write a Playbook: The Step-by-Step Mastery Ladder

> ⏱️ **Time to complete: ~14 hrs total** (overlaps files 01–10 — treat this as the *hands-on track* running alongside the theory files) — 12 steps × 30–90 min each
> 📦 **Covers:** writing playbooks **in small incremental steps** — from a 3-line `ping` play to a production zero-downtime deploy written from memory. Each step: one new concept, one exercise, one checkpoint.
>
> **How to use:** do ONE step per sitting. Type every exercise — never copy-paste. If the checkpoint fails, redo the exercise before moving on. Steps 1–8 build syntax reflexes; steps 9–12 build production judgment.

---

## The golden rules (read before step 1, revisit after step 12)

1. **Name everything** — plays, tasks, handlers. Logs are read at 3 a.m.
2. **Idempotent or it doesn't ship** — second run must report `changed=0`.
3. **Use modules, not shell** — `shell` only with `changed_when`/`creates` + a comment why.
4. **Validate before you restart** — `validate:` on every config change.
5. **Verify after you change** — a health check ends every deploy play.
6. **Blast radius on purpose** — `serial`, `--limit`, `--list-hosts` before every prod run.
7. **Secrets never in plaintext** — Vault/lookups + `no_log` from day one.
8. **Check mode first** — if it breaks `--check --diff`, it's not production-ready.

---

## STEP 1 — Your first playbook (structure reflex)
*Concepts: play, hosts, tasks, module invocation, running a playbook (deep dive: file 01)*

```yaml
# 01-first.yml
- name: My first play
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Say hello
      ansible.builtin.debug:
        msg: "Hello from {{ inventory_hostname }}"
```

```bash
ansible-playbook 01-first.yml
```

**🧪 Exercise:** change the message to include today's date via a second task using `ansible.builtin.command: date` + `register`, then print `result.stdout` in the debug.

**✅ Checkpoint:** You can explain — what a play is, why `connection: local` is here, and what changed between runs.

---

## STEP 2 — Make a real change (modules & idempotency)
*Concepts: state modules, `state: present/absent`, the recap (deep dive: file 01/03)*

```yaml
# 02-idempotent.yml
- name: Install and start nginx
  hosts: localhost
  connection: local
  become: true
  tasks:
    - name: Install nginx
      ansible.builtin.apt:
        name: nginx
        state: present
        update_cache: true

    - name: Ensure nginx is running
      ansible.builtin.service:
        name: nginx
        state: started
        enabled: true
```

**🧪 Exercise:** run it **twice**. First run: `changed=2`. Second: `changed=0`. Then flip one task to `state: absent`, run, flip back.

**✅ Checkpoint:** You can say *why* the second run changed nothing — in one sentence, using the words "desired state" and "diff".

---

## STEP 3 — Deploy a file (copy, content, notify)
*Concepts: file state, change detection, handlers (deep dive: file 03)*

```yaml
# 03-file.yml
- name: Serve a homepage
  hosts: localhost
  connection: local
  become: true
  tasks:
    - name: Deploy homepage
      ansible.builtin.copy:
        content: "Hello from {{ inventory_hostname }}\n"
        dest: /var/www/html/index.html
        mode: "0644"
      notify: Reload nginx

    - name: Ensure nginx running
      ansible.builtin.service:
        name: nginx
        state: started
        enabled: true

  handlers:
    - name: Reload nginx
      ansible.builtin.service:
        name: nginx
        state: reloaded
```

**🧪 Exercise:** (a) run → change the content → run again → watch ONE reload happen. (b) Change content twice in the same run (two copy tasks, same handler) → prove the handler fires **once**.

**✅ Checkpoint:** You can explain handler timing: dedup, changed-only, end-of-play — and `meta: flush_handlers` fixes which of those?

---

## STEP 4 — React to the world (register + when)
*Concepts: registering results, conditionals, stat (deep dive: files 03/05)*

```yaml
# 04-register-when.yml
- name: Conditional maintenance
  hosts: localhost
  connection: local
  become: true
  tasks:
    - name: Check if marker exists
      ansible.builtin.stat:
        path: /etc/maintenance-mode
      register: marker

    - name: Tell me what I found
      ansible.builtin.debug:
        msg: "Maintenance mode is ON"
      when: marker.stat.exists

    - name: Disk full check
      ansible.builtin.command: df --output=pcent /
      register: disk
      changed_when: false

    - name: Warn if disk > 80%
      ansible.builtin.debug:
        msg: "DISK WARNING: {{ disk.stdout }}"
      when: disk.stdout | regex_findall('(\d+)%') | first | int > 80
```

**🧪 Exercise:** create/remove the marker file and see the branch flip. Add a `failed_when` to the disk task that fails when usage > 90%.

**✅ Checkpoint:** You can explain `changed_when: false` on the read-only command — why does it matter for reports and handlers?

---

## STEP 5 — Repeat yourself (loops)
*Concepts: loop, item, dict2items, loop_control (deep dive: file 05)*

```yaml
# 05-loops.yml
- name: Batch operations
  hosts: localhost
  become: true
  vars:
    packages: [curl, git, htop]
    users:
      alice: { shell: /bin/bash }
      bob:   { shell: /bin/zsh }
  tasks:
    - name: Install packages
      ansible.builtin.apt:
        name: "{{ item }}"
        state: present
      loop: "{{ packages }}"

    - name: Create users from a dict
      ansible.builtin.user:
        name: "{{ item.key }}"
        shell: "{{ item.value.shell }}"
        state: present
      loop: "{{ users | dict2items }}"
      loop_control:
        label: "{{ item.key }}"
```

**🧪 Exercise:** add `index_var` and print position; then make one package name invalid and watch the loop fail per-item — note which items still ran.

**✅ Checkpoint:** dict loop via `dict2items` without peeking; `label` improves logs — what's the risk if labels contain secrets?

---

## STEP 6 — Parameterize (variables & precedence)
*Concepts: vars, vars_files, -e, set_fact, defaults (deep dive: file 04)*

```yaml
# 06-vars.yml
- name: Variable playground
  hosts: localhost
  connection: local
  gather_facts: false
  vars:
    env: play
    port: 8080
  tasks:
    - name: Task-level override wins locally
      ansible.builtin.debug: { msg: "task sees {{ port }}" }
      vars: { port: 9090 }

    - name: Play still sees its own
      ansible.builtin.debug: { msg: "play sees {{ port }}" }

    - name: Runtime fact
      ansible.builtin.set_fact:
        runtime_var: "computed-{{ env }}"

    - name: Show it
      ansible.builtin.debug: { msg: "{{ runtime_var }} — but -e beats me!" }
```

```bash
ansible-playbook 06-vars.yml
ansible-playbook 06-vars.yml -e "env=cli port=7777"   # -e wins everywhere
```

**🧪 Exercise:** run with and without `-e`. Move `vars:` into a `vars_file.yml` and load with `vars_files:`. Confirm the ranking you observe against the ladder in file 04.

**✅ Checkpoint:** Recite: `-e` → set_fact/registered → task > block > role vars > vars_files > play vars > … > role defaults.

---

## STEP 7 — Branch on facts (OS-aware playbooks)
*Concepts: gather_facts, ansible_facts, os_family (deep dive: file 04)*

```yaml
# 07-facts.yml
- name: OS-aware install
  hosts: localhost
  become: true
  tasks:
    - name: Debian family
      ansible.builtin.apt:
        name: nginx
        state: present
      when: ansible_facts['os_family'] == "Debian"

    - name: RedHat family
      ansible.builtin.dnf:
        name: nginx
        state: present
      when: ansible_facts['os_family'] == "RedHat"

    - name: Show my key facts
      ansible.builtin.debug:
        msg: "{{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }} · {{ ansible_facts['default_ipv4']['address'] }} · {{ ansible_facts['memtotal_mb'] }}MB"
```

**🧪 Exercise:** run `ansible localhost -m setup -a "gather_subset=!all,network"` and find three facts you didn't know; use one in a debug msg.

**✅ Checkpoint:** Why `ansible_facts['os_family']` over the legacy `ansible_os_family`? (Modern dict interface; underscore aliases are compat shims.)

---

## STEP 8 — Generate config (templates + validate)
*Concepts: template, Jinja2 basics, validate (deep dive: file 06)*

```jinja
{# templates/health.conf.j2 #}
env={{ env }}
workers={{ ansible_facts['processor_count'] * 2 + 1 }}
endpoint={{ endpoint | default('http://localhost:8080') }}
```

```yaml
# 08-template.yml
- name: Render config safely
  hosts: localhost
  connection: local
  vars:
    env: dev
  tasks:
    - name: Render app config
      ansible.builtin.template:
        src: templates/health.conf.j2
        dest: /tmp/health.conf
        mode: "0644"
        validate: "python3 -c 'import sys; open(sys.argv[1]).read()' %s"   # stand-in validator
```

**🧪 Exercise:** add `{% if env == 'prod' %}debug=false{% else %}debug=true{% endif %}` and render with `-e env=prod`. Break the template syntax on purpose and read the error carefully.

**✅ Checkpoint:** In `when:` you write bare expressions; in templates `{{ }}`. Why does `validate:` matter even more for nginx/postgres configs than here?

---

## 🏁 STEP 9 — Orchestrate multiple hosts (multi-play + serial)
*Concepts: plays in sequence, groups, delegate_to, serial (deep dives: files 02/05/10)*

```yaml
# 09-orchestrate.yml  (run against your lab: -i "node1,node2,node3,")
- name: 1. Prep all nodes
  hosts: all
  become: true
  tasks:
    - name: Baseline package
      ansible.builtin.apt:
        name: curl
        state: present

- name: 2. Config the "db" node only
  hosts: all
  tasks:
    - name: Only on first host
      ansible.builtin.debug:
        msg: "I am the leader: {{ inventory_hostname }}"
      run_once: true
      delegate_to: "{{ groups['all'][0] }}"

- name: 3. Rolling restart, two at a time
  hosts: all
  become: true
  serial: 2
  tasks:
    - name: Touch a rollback marker
      ansible.builtin.file:
        path: /tmp/deployed-{{ ansible_date_time.date }}
        state: touch
        mode: "0644"
```

**🧪 Exercise:** change `serial: 2` → `serial: [1, "50%"]` and watch the waves in the output header. Break one host's SSH (stop the container) and observe how serial contains the failure.

**✅ Checkpoint:** You can narrate: plays run in order; each play re-targets; `serial` batches contain blast radius.

---

## 🏁 STEP 10 — Fail well (block/rescue/always + retries)
*Concepts: error paths, rollback, until (deep dive: file 08)*

```yaml
# 10-errors.yml
- name: Deploy with a safety net
  hosts: localhost
  connection: local
  become: true
  vars:
    release: v2
  tasks:
    - name: Record previous state
      ansible.builtin.command: cat /tmp/current-release
      register: prev
      failed_when: false
      changed_when: false

    - name: Deploy
      block:
        - name: Simulate deploy
          ansible.builtin.copy:
            content: "{{ release }}\n"
            dest: /tmp/current-release

        - name: Simulated health check (will fail)
          ansible.builtin.uri:
            url: "http://localhost:9999/healthz"
            status_code: 200
          register: health
          until: health.status == 200
          retries: 2
          delay: 1

      rescue:
        - name: Roll back
          ansible.builtin.copy:
            content: "{{ prev.stdout | default('v1') }}\n"
            dest: /tmp/current-release

        - name: Alert
          ansible.builtin.debug:
            msg: "Rolled back — failed at: {{ ansible_failed_task.name }}"

      always:
        - name: Telemetry (always runs)
          ansible.builtin.debug:
            msg: "deploy attempt for {{ release }} finished"
```

**🧪 Exercise:** make the health check pass (point it at real nginx) → rescue never runs. Break it → watch rollback. Make the *rollback* fail → confirm the host ends failed.

**✅ Checkpoint:** You can state the three block semantics cold: when rescue runs, when always runs, what a failing rescue means.

---

## 🏁 STEP 11 — Package it (turn steps 2–8 into a ROLE)
*Concepts: role tree, defaults vs vars, meta (deep dive: file 07)*

```bash
ansible-galaxy init roles/myapp
```

Move your step-8 template + tasks into:

```
roles/myapp/
├── defaults/main.yml    # env, port — overridable knobs
├── tasks/main.yml       # your install/configure/verify tasks
├── templates/health.conf.j2
├── handlers/main.yml
└── meta/main.yml
```

```yaml
# 11-role.yml
- hosts: localhost
  connection: local
  become: true
  roles:
    - role: myapp
      vars: { env: staging }     # role params — highest 'static' override
```

**🧪 Exercise:** override `env` three ways — role params, play vars, `-e` — and confirm the winner each time. Add a second role dependency in `meta/`.

**✅ Checkpoint:** You can place any new knob in defaults vs vars without hesitation, and explain why.

---

## 🏁 STEP 12 — The capstone: zero-downtime deploy FROM MEMORY
*Everything comes together (deep dives: files 08/10; see also cookbook project 2)*

Close all files. On a blank editor, write a play that does **all** of:

1. `serial: [1, "50%"]` + `max_fail_percentage: 0`
2. Per host: drain from LB (`delegate_to: localhost`) → versioned release dir + symlink flip → config `template` with `validate:` → handler restart → `meta: flush_handlers` → health check with `until/retries` → re-enable in LB
3. `block/rescue`: capture previous release first; on failure roll back symlink + restart + verify; `always`: telemetry
4. Final `post_tasks`: smoke test through the LB

**✅ Checkpoint (the mastery bar):** You wrote it in ≤ 20 minutes, it lints clean (`ansible-lint`), runs green on your lab, and the re-run reports `changed=0`. If yes — **you can write playbooks at SDE-3 level.** Go deep on file 10/16 polish and interview narration.

---

## 📅 The daily drill (after the ladder)

| Drill | Time |
|---|---|
| Write step-12 capstone from memory | 20 min |
| Re-run yesterday's exercise; confirm `changed=0` | 5 min |
| One file-17 rapid-fire section out loud | 10 min |

## ⚠️ Ladder-wide pitfalls (each step guards one)

| Step | Pitfall it inoculates against |
|---|---|
| 1–2 | Copy-paste learning; not verifying idempotency |
| 3 | Unnamed tasks; handler myths |
| 4 | `ignore_errors` without follow-up; false `changed` |
| 5 | Looping strings; `when`+`loop` confusion |
| 6 | Using `set_fact` as a config knob |
| 7 | Legacy underscore facts everywhere |
| 8 | No `validate:` on service configs |
| 9 | Orchestration inside one play with `strategy: free` |
| 10 | Rollback that isn't verified |
| 11 | Knobs hidden in `vars/main.yml` |
| 12 | "It works on my laptop" code that fails `--check` or lint |

**➡️ Next:** [01 — Fundamentals & Architecture](01-fundamentals.md) (theory track)
