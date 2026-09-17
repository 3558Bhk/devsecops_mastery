# 03 — Playbook Fundamentals (The Daily Driver)

> ⏱️ **Time to complete: ~2.5 hrs** — read 25 min · practice 90 min · self-quiz 35 min
> 📦 **Covers:** play anatomy & execution order (pre_tasks → roles → tasks → post_tasks → handlers) · the 12 everyday modules · register & result objects · handler semantics (dedup, flush_handlers) · the full production app-release playbook · check/diff mode & the safe-run workflow · multi-play orchestration · verification tasks

> **Interview framing:** This is where they hand you a marker: *"Write a playbook to deploy X."* You need flawless muscle memory for tasks, handlers, register, and verification.

---

## 1. Anatomy of a play (label everything)

```yaml
- name: Deploy API servers                # 1. play name — always
  hosts: api                              # 2. target (pattern)
  become: true                            # 3. privilege escalation
  gather_facts: true                      # 4. facts (default true)
  vars:                                   # 5. play-scope variables
    app_version: "1.8.2"
  tasks:                                  # 6. ordered task list
    - name: Download release artifact     # 7. EVERY task gets a name
      ansible.builtin.get_url:
        url: "https://artifacts.internal/api/{{ app_version }}.tar.gz"
        dest: "/tmp/api-{{ app_version }}.tar.gz"
        mode: "0644"
      register: download                  # 8. capture result

    - name: Show what happened on failure
      ansible.builtin.debug:
        msg: "Download failed: {{ download.msg }}"
      when: download is failed
  handlers:                               # 9. run at end of play if notified
    - name: Restart api
      ansible.builtin.service: { name: api, state: restarted }
```

Execution order within a play: `pre_tasks` → `roles` → `tasks` → `post_tasks` → **handlers** (at the end, once each).

---

## 2. The 12 modules that cover 80% of daily work

| Module | Declarative job | Killer args |
|---|---|---|
| `apt` / `yum` / `dnf` / `package` | packages | `name`, `state: present/absent/latest`, `update_cache` |
| `service` / `systemd_service` | services | `state: started/stopped/restarted/reloaded`, `enabled` |
| `copy` | push local content/file | `content`, `dest`, `mode`, `backup: true`, `validate` |
| `template` | push rendered Jinja2 | `src` (`.j2`), `validate` |
| `file` | file/dir/symlink state | `state: directory/touch/absent/link`, `owner`, `mode` |
| `lineinfile` | ensure one line exists | `regexp`, `line`, `insertafter`, `create` |
| `blockinfile` | managed block of lines | `marker`, `insertafter` |
| `get_url` | download | `checksum: sha256:...`, `mode` |
| `unarchive` | extract tar/zip | `remote_src: true` (extract a file already on target) |
| `stat` | inspect file (no change) | use with `register` + `when` |
| `uri` | HTTP calls / health checks | `status_code`, `body_format: json`, `method` |
| `user` / `group` | users | `shell`, `groups`, `generate_ssh_key`, `password_hash` |

Plus: `cron`, `mount` (ansible.posix), `sysctl`, `reboot`, `wait_for`, `wait_for_connection`, `ansible.posix.firewalld` / `community.general.ufw`, `ansible.posix.seboolean`, `community.general.ini_file`, `hostname`.

---

## 3. 🎬 SCENARIO 1 — "Deploy an app release" (the full production pattern)

> *"Your app is a tarball in an internal artifact store. Deploy it, wire config, restart safely, verify health. This is the most common whiteboard task."*

```yaml
- name: Release {{ app_version }} to api tier
  hosts: api
  become: true
  vars:
    app_version: "1.8.2"
    install_dir: /opt/api
    artifact_url: "https://artifacts.internal/api-{{ app_version }}.tar.gz"

  tasks:
    - name: Fetch release notes marker (idempotent download)
      ansible.builtin.get_url:
        url: "{{ artifact_url }}"
        dest: "/tmp/api-{{ app_version }}.tar.gz"
        checksum: "sha256:https://artifacts.internal/api-{{ app_version }}.sha256"
        mode: "0644"
      register: artifact

    - name: Extract release into a VERSIONED directory
      ansible.builtin.unarchive:
        src: "/tmp/api-{{ app_version }}.tar.gz"
        dest: "{{ install_dir }}/releases/{{ app_version }}"
        remote_src: true
        creates: "{{ install_dir }}/releases/{{ app_version }}/bin/api"   # skip if done
      notify: Restart api

    - name: Render config from template
      ansible.builtin.template:
        src: api.conf.j2
        dest: "{{ install_dir }}/shared/api.conf"
        mode: "0640"
        owner: api
        validate: "{{ install_dir }}/bin/api --config-check %s"    # fail BEFORE restart
      notify: Restart api

    - name: Atomically flip the current symlink
      ansible.builtin.file:
        src: "{{ install_dir }}/releases/{{ app_version }}"
        dest: "{{ install_dir }}/current"
        state: link
        force: true
      notify: Restart api

    - name: Start service (idempotent start)
      ansible.builtin.service:
        name: api
        state: started
        enabled: true

    - name: Flush handlers NOW so health check sees the new binary
      ansible.builtin.meta: flush_handlers

    - name: Wait for app to come up
      ansible.builtin.wait_for:
        port: 8080
        delay: 2
        timeout: 60

    - name: Health check against the real endpoint
      ansible.builtin.uri:
        url: "http://localhost:8080/healthz"
        status_code: 200
      register: health
      until: health.status == 200
      retries: 5
      delay: 3
      changed_when: false

  handlers:
    - name: Restart api
      ansible.builtin.service:
        name: api
        state: restarted
```

**The 6 things to call out when you present this:**

1. **`creates:`** makes the extract idempotent — re-run skips completed hosts.
2. **Versioned releases + symlink flip** = instant rollback is `ln -sfn` to the previous release (file 16 uses this for blue-green).
3. **`validate:`** — never restart a service with a broken config; fail the task before touching the process.
4. **Handlers batch** — config + binary + symlink changes = exactly **one** restart, even though three tasks notify it.
5. **`meta: flush_handlers`** — force handlers mid-play so the health check validates the *new* state.
6. **`until/retries/delay`** — tolerate slow boots instead of flapping failures.

---

## 4. `register` — reading the world

Every task result is a rich object:

```yaml
- name: Check if config exists
  ansible.builtin.stat:
    path: /etc/api/api.conf
  register: cfg

- ansible.builtin.debug:
    msg: "exists={{ cfg.stat.exists }} mode={{ cfg.stat.mode }}"

- name: Get kernel info
  ansible.builtin.command: uname -r
  register: kernel
  changed_when: false

- ansible.builtin.debug:
    msg: "rc={{ kernel.rc }} stdout={{ kernel.stdout }}"
```

Fields you'll actually use: `.rc`, `.stdout`, `.stdout_lines`, `.stderr`, `.changed`, `.failed`, `.skipped`, `.stat.*`, `.status` (uri), `.results` (loops). Full dump with `-vv` or `debug: var=result`.

---

## 5. Handlers — the semantics interviewers probe

```yaml
tasks:
  - name: touch config a
    ansible.builtin.copy: { content: "a\n", dest: /tmp/a.conf }
    notify: restart app
  - name: touch config b
    ansible.builtin.copy: { content: "b\n", dest: /tmp/b.conf }
    notify: restart app          # same handler AGAIN
handlers:
  - name: restart app
    ansible.builtin.service: { name: app, state: restarted }
```

- Notified twice → runs **once** (deduplicated per play).
- Only runs if a notifying task actually **changed**.
- Runs **after all tasks in the play** (not inline) unless you `meta: flush_handlers`.
- Failed task earlier in the play → handlers don't run on that host (`--force-handlers` overrides; a `block: always:` section also works — file 08).
- Group handlers with `listen:` — notify a *topic*: `notify: "deploy app"` can trigger many handlers.

---

## 6. Controlling runs like an operator

```bash
ansible-playbook site.yml --list-tasks            # dry map of tasks
ansible-playbook site.yml --list-hosts            # blast radius
ansible-playbook site.yml --list-tags
ansible-playbook site.yml --start-at-task='Render config'
ansible-playbook site.yml --step                  # confirm each task
ansible-playbook site.yml --check --diff          # plan + show would-be file diffs
ansible-playbook site.yml --limit api[0]          # one host first
ansible-playbook site.yml -e app_version=1.8.3    # override vars
ansible-playbook site.yml -v / -vv / -vvv / -vvvv # verbosity (SSH debug = -vvv)
ansible-playbook site.yml --forks 50              # parallelism override
```

`--check --diff` deserves a speech: *"It's `terraform plan` for config management. In prod I always run check+diff, review the diff, then apply. Some tasks can't be checked (side effects external to files) — you exempt them with `check_mode: false`."*

---

## 7. 🎬 SCENARIO 2 — Multi-host orchestration (play ordered, not task ordered)

> *"Front the DB maintenance: stop writes on the app tier, run DB migration once, start app tier."*

```yaml
- name: 1. Quiesce app tier
  hosts: api
  become: true
  tasks:
    - ansible.builtin.service: { name: api, state: stopped }

- name: 2. Run migration once
  hosts: db[0]                       # just the leader
  become: true
  tasks:
    - ansible.builtin.command: /opt/db/bin/migrate --up
      register: mig
      changed_when: "'applied' in mig.stdout"     # honest reporting

- name: 3. Bring app tier back and verify
  hosts: api
  become: true
  serial: 2                          # rolling (file 10)
  tasks:
    - ansible.builtin.service: { name: api, state: started }
    - ansible.builtin.uri: { url: "http://localhost:8080/healthz", status_code: 200 }

- name: 4. Notify
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Post completion message
      ansible.builtin.uri:
        url: "https://hooks.slack.com/services/XXX"
        method: POST
        body_format: json
        body: '{"text":"API migration {{ mig.stdout_lines | default(['n/a']) | join(' ') }} complete"}'
```

> 💬 **Say:** *"Multi-play playbooks are Ansible's orchestration superpower — each play has its own target, become, and batch size. The migration `run_once`-style targeting via `db[0]` avoids running DDL N times. Note step 4 references `mig` — a var from another play/host requires `hostvars`; here I kept it simple, but I'd use `hostvars[groups['db'][0]].mig` to be precise."*

---

## 8. 🎤 SDE-3 Interview Corner

**Q1. Play vs task vs module vs role?**
> Module = unit of work (Python). Task = one module call. Play = tasks mapped to hosts with scope (vars/become/serial). Playbook = file of plays. Role = reusable packaging of all of it.

**Q2. When do handlers run exactly, and how do you force them early?**
> End of the play's task phase, deduplicated, changed-only. `meta: flush_handlers` runs pending ones immediately. In blocks, `always:` sections and `--force-handlers` matter on failure (file 08).

**Q3. Your playbook reports `changed` on every run for a `command` task. Fixes?**
> Prefer a real module; or `creates:`/`removes:`; or `changed_when: <honest condition>`; for read-only probes `changed_when: false`. False-changed pollutes reports and triggers spurious handler runs — treat as a defect.

**Q4. How do you safely test a playbook against prod?**
> `--syntax-check` → `--check --diff` on a canary `--limit` → review diff → apply to canary with `serial` → health-check → roll forward. Plus lint + Molecule in CI (file 14).

**Q5. What breaks in `--check` mode?**
> Anything whose state can't be diffed: package installs are fine (module simulates), but `command`/`shell`/`uri POST` tasks have no model — they'd be skipped; some playbooks `when: not ansible_check_mode` around them or set `check_mode: false` deliberately.

---

## ⚠️ Common pitfalls

- No `name:` on tasks → unreadable logs; ansible-lint fails it. 
- `shell` everywhere (injection + non-idempotent) instead of proper modules.
- Forgetting that handlers don't run if the play **failed** — pair with `block/always` when cleanup matters.
- `register` on a loop gives `.results[]` — indexing `result.stdout` crashes with "no attribute stdout"; use `result.results[0]`.
- Hardcoded `state: restarted` in the main service task → restarts on every run even when nothing changed. Use `started` + notify handler.
- Secrets echoed by `debug` → pair with `no_log: true` (file 09).

---

**➡️ Next:** [04 — Variables & Facts (the precedence game)](04-variables-facts.md)
