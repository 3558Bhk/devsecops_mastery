# 08 — Error Handling, Blocks & Rollbacks (The Senior-Signal Topic)

> ⏱️ **Time to complete: ~2 hrs** — read 30 min · practice (run the rollback playbook!) 90 min · self-quiz 20 min
> 📦 **Covers:** failed_when / changed_when / ignore_errors done right · any_errors_fatal & max_fail_percentage · block/rescue/always semantics (incl. ansible_failed_task) · the **full zero-downtime deploy with automatic rollback** · force_handlers · rollback design Q&A

> **Interview framing:** Junior playbooks assume happiness. SDE-3 playbooks are designed for failure: detect it, contain it, roll back, and alert. This file is the difference between "writes YAML" and "runs production automation".

---

## 1. The five failure-control tools

| Tool | Meaning |
|---|---|
| `ignore_errors: true` | Task fails → play continues (host marked with failure state) |
| `failed_when: <expr>` | **You** define what failure means (default: module returns `failed`) |
| `changed_when: <expr>` | You define what "changed" means (honesty for `command`/`shell`) |
| `ignore_unreachable: true` | Host SSH-unreachable → continue (mark unreachable) |
| `any_errors_fatal: true` | Any host failure → abort the whole play on all hosts |

And for batches: **`max_fail_percentage: 20`** — with `serial`, tolerate up to N% failures per batch before aborting (must be > 0 to allow any failures).

```yaml
- name: Health check with custom failure semantics
  ansible.builtin.uri:
    url: "http://localhost:8080/healthz"
    status_code: 200
  register: health
  failed_when: health.status != 200 or 'degraded' in health.json.state

- name: Best-effort cleanup
  ansible.builtin.command: /usr/local/bin/cleanup
  ignore_errors: true
  register: cleanup
  changed_when: false

- name: Escalate if cleanup failed
  ansible.builtin.debug:
    msg: "cleanup failed but deploy continues — check logs"
  when: cleanup is failed
```

> 💬 **Say:** *"`ignore_errors` without a `register` + follow-up decision is how silent outages happen. Every ignored error must be acknowledged — re-registered, logged, or escalated."*

---

## 2. `block / rescue / always` — try / except / finally

```yaml
tasks:
  - name: Risky deployment
    block:
      - name: Deploy steps
        ansible.builtin.import_tasks: tasks/deploy.yml      # any failure jumps to rescue
      - name: Post-deploy health check
        ansible.builtin.uri: { url: "http://localhost:8080/healthz", status_code: 200 }

    rescue:
      - name: Roll back to previous release
        ansible.builtin.import_tasks: tasks/rollback.yml

      - name: Alert the on-call
        ansible.builtin.uri:
          url: "{{ slack_webhook }}"
          method: POST
          body_format: json
          body: '{"text":"🚨 deploy FAILED on {{ inventory_hostname }}, rolled back"}'
        delegate_to: localhost
        run_once: false

    always:
      - name: Re-enable in LB no matter what
        ansible.builtin.uri:
          url: "http://lb-ctl:9999/enable/{{ inventory_hostname }}"
          method: POST
      - name: Always collect diagnostics
        ansible.builtin.command: journalctl -u api -n 200
        register: diag
        changed_when: false
```

Semantics you must be precise about:

- **`rescue` runs only on task failure inside `block`** (not on unreachable hosts — those skip; not on handlers).
- If a **`rescue` task itself fails** → the play fails for that host (rollback failure is a real emergency).
- **`always` runs even when block succeeded** — put cleanup/telemetry there, not state changes you only want on failure.
- A task that fails in rescue → host failed **even if a later rescue task succeeds** — there's no "recovery marker"; the failure sticks for the play's accounting (you can use `meta: end_host` patterns or ignore_errors strategically).
- Inside `rescue`, two magic vars are available: **`ansible_failed_task`** (name/attrs) and **`ansible_failed_result`** (the result object) — use them in alerts.
- Blocks can nest (block in rescue), and `when` on a block applies to all contained tasks.

---

## 3. 🎬 SCENARIO — Full zero-downtime deploy with automatic rollback

> *The complete pattern: drain → deploy → verify → rollback on failure → re-enable always. This is THE SDE-3 playbook. Know it cold.*

```yaml
- name: Rolling release with auto-rollback
  hosts: web
  become: true
  serial: 2                                  # blast radius: 2 hosts per wave
  max_fail_percentage: 0                     # any failure in wave aborts further waves
  any_errors_fatal: true
  vars:
    release: "{{ app_version }}"             # injected with -e in CI
    keep_releases: 3

  tasks:
    - name: Get current release before touching anything
      ansible.builtin.command: readlink /opt/app/current
      register: prev_release
      changed_when: false
      failed_when: false                     # first deploy: no current yet

    - name: Remember previous release path
      ansible.builtin.set_fact:
        previous_release: "{{ prev_release.stdout | default('') }}"

    - name: Deploy
      block:
        - name: Drain host from load balancer
          ansible.builtin.uri:
            url: "http://{{ hostvars[groups['lb'][0]].ansible_host }}:9999/servers/{{ inventory_hostname }}/drain"
            method: POST
          delegate_to: localhost
          run_once: false
          changed_when: true

        - name: Let in-flight requests finish
          ansible.builtin.pause: { seconds: 10 }

        - name: Unpack new release
          ansible.builtin.unarchive:
            src: "artifacts/app-{{ release }}.tar.gz"
            dest: "/opt/app/releases/{{ release }}"
            creates: "/opt/app/releases/{{ release }}/current_build"

        - name: Flip symlink
          ansible.builtin.file:
            src: "/opt/app/releases/{{ release }}"
            dest: /opt/app/current
            state: link
            force: true
          notify: Restart app

        - name: Run handlers now (restart)
          ansible.builtin.meta: flush_handlers

        - name: Wait for port
          ansible.builtin.wait_for: { port: 8080, timeout: 60 }

        - name: Health check (the acceptance gate)
          ansible.builtin.uri:
            url: "http://localhost:8080/healthz"
            status_code: 200
          register: health
          until: health.status == 200
          retries: 6
          delay: 5

      rescue:
        - name: Roll back symlink to previous release
          when: previous_release | length > 0
          ansible.builtin.file:
            src: "{{ previous_release }}"
            dest: /opt/app/current
            state: link
            force: true
          notify: Restart app

        - name: Flush rollback restart
          ansible.builtin.meta: flush_handlers

        - name: Verify rollback health
          ansible.builtin.uri:
            url: "http://localhost:8080/healthz"
            status_code: 200
          retries: 6
          delay: 5
          register: rb_health
          until: rb_health.status == 200

        - name: Page the on-call with context
          ansible.builtin.uri:
            url: "{{ slack_webhook | mandatory }}"
            method: POST
            body_format: json
            body:
              text: "🚨 {{ inventory_hostname }}: release {{ release }} failed ({{ ansible_failed_task.name }}), rolled back to {{ previous_release | default('none') }}"
          delegate_to: localhost

      always:
        - name: Re-enable host in LB (even on rollback — it's healthy again)
          ansible.builtin.uri:
            url: "http://{{ hostvars[groups['lb'][0]].ansible_host }}:9999/servers/{{ inventory_hostname }}/enable"
            method: POST
          delegate_to: localhost

        - name: Prune old releases (keep last N)
          ansible.builtin.shell: |
            ls -1dt /opt/app/releases/* | tail -n +$(( {{ keep_releases }} + 1 )) | xargs -r rm -rf
          args: { executable: /bin/bash }
          changed_when: true
          tags: cleanup

  handlers:
    - name: Restart app
      ansible.builtin.service:
        name: app
        state: restarted
```

**Talking points when you present it (practice this narration):**

1. **`serial: 2` + `max_fail_percentage: 0`** — "waves of 2; a single failure stops new waves — the fleet can't be fully destroyed by one bad release."
2. **Capture `previous_release` first** — "you can only roll back to what you recorded before mutating."
3. **Drain → deploy → health → enable** — "users never hit a broken backend; health is an acceptance gate, not a formality."
4. **rescue = deterministic rollback** — "symlink flip back + restart + verify rollback. If rollback verification fails, the host stays failed — loudly."
5. **`always` re-enables the LB member** — "cleanup and restoration are unconditional; telemetry in `always`, state transitions in block/rescue."
6. **`ansible_failed_task` in the alert** — "the pager says WHAT broke, not just that something did."
7. **Release pruning** — "bounded disk usage; keep_releases also defines my rollback depth."

---

## 4. Failed-handlers semantics (the subtle stuff)

```yaml
- hosts: all
  force_handlers: true        # even on play failure, notified handlers run
  tasks:
    - name: change config
      ansible.builtin.template: { src: t.j2, dest: /etc/x.conf }
      notify: restart x
    - name: this fails
      ansible.builtin.command: /bin/false
```

- Default: failed play → handlers **don't run** → config changed but service not restarted = **drift**. `force_handlers: true` (or `--force-handlers`) reverts that.
- Alternative: put critical notifications inside `block/always`.
- **If a handler fails**, the play fails at that point for the host — handler failures are real failures.

---

## 5. 🎤 SDE-3 Interview Corner

**Q1. Design a rollback strategy for a config-file deployment across 500 hosts.**
> Before each write: `copy: backup: true` or capture checksum/`cp` to `.prev`; validate with `validate:`; flip only after validation; wrap in block/rescue that restores `.prev` and notifies reload; `serial` waves with health gates; report aggregate status at end. If config is in git (it should be), rollback = deploy previous git ref — deterministic and reviewable.

**Q2. `ignore_errors` vs `failed_when` — when do you use each?**
> `failed_when` when I can define success better than the module (HTTP 200 but "degraded" body; grep found a bad pattern). `ignore_errors` only for genuinely optional steps (telemetry, best-effort cleanup) — always paired with register + follow-up. Using `ignore_errors` as a "make it pass" button is an anti-pattern I've cleaned up before.

**Q3. How do you stop a fleet-wide rollout mid-way?**
> Ctrl-C once = stop scheduling new tasks, finish in-flight; Ctrl-C twice = hard abort (leaves partial state — that's why resumability matters). `serial` waves mean aborting leaves earlier waves complete; `--start-at-task` + idempotent tasks = resume safely. `any_errors_fatal` gives automatic stopping.

**Q4. Host is unreachable mid-play — what happens to its handlers/tasks?**
> Host is removed from the active batch; remaining tasks skip it; handlers don't run for it. `ignore_unreachable: true` continues the play but the host stays marked. Pattern: dedicated `wait_for_connection` play + retry wrapper at platform level.

**Q5. How do you make a playbook re-runnable after a mid-deploy crash?**
> Idempotent tasks everywhere, `creates:` guards, symlink-based releases (flip is atomic), no `state: restarted` outside handlers, and a `pre_tasks` section that detects half-applied state (e.g., release dir exists but symlink stale) and reconciles. Re-run = converge, not redo.

---

## ⚠️ Common pitfalls

- `rescue` that doesn't verify the rollback — you traded a broken deploy for a broken rollback silently.
- Putting **state-changing tasks** in `always:` (they run on success too — it's `finally`, not `on-error`).
- `max_fail_percentage: 0` misunderstanding — 0 means *any* failure aborts (percentage must be exceeded to continue).
- Forgetting that `block`'s `when` propagates to all children — rescue conditions get confusing fast; keep blocks small.
- Relying on handlers for cleanup after failure without `force_handlers`/`always`.
- Alerts inside `rescue` using `delegate_to: localhost` without `run_once` consideration → 500 pagers for 500 hosts (usually you want one aggregated summary play at the end instead).

---

**➡️ Next:** [09 — Vault & Secrets Management](09-vault-secrets.md)
