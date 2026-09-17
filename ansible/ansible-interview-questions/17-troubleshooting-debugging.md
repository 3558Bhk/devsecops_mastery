# 17 — 🔴 Troubleshooting & Debugging Drills (14 drills)

> "It's broken — walk me through your diagnosis." Answer as: **reproduce → narrow layer → hypothesis → verify → fix → prevent**. Course ref: [11-performance-tuning.md](../ansible-mastery/11-performance-tuning.md) · [04-variables-facts.md](../ansible-mastery/04-variables-facts.md)

## 🎬 D1. `FAILED! => ... to use the ssh connection type with a password` / auth failures on one host
> **Layers:** can I `ssh user@host` manually? → key present? → `ansible_user`/`ansible_port` correct in inventory? → known_hosts/host-key changed? (`--ssh-extra-args -o StrictHostKeyChecking=accept-new` for TOFU) → sudo/become password? Verbose `-vvvv` shows the exact SSH invocation. **Prevent:** pinned known_hosts, per-host `host_vars` for connection quirks.

## 🎬 D2. "module_stdout" JSON decode error on every task for one host
> A: Something is printing to stdout on SSH login — a user login banner (`/etc/profile.d`, motd scripts) or a broken Python. `ssh user@host python3 --version` and check shell init. **Fix:** silence/fix the banner or set `interpreter_python`. Classic and interviewers love it.

## 🎬 D3. Playbook works for 5 hosts, times out at 500
> A: Not a bug — a scale wall. Check: control-node CPU/fds at that fork count, SSH `MaxStartups` storms, fact-gathering serialization, dynamic inventory API latency. Apply file-11 ladder: pipelining, forks sizing, fact caching, mesh/execution nodes. **Verify:** timer callback before/after.

## 🎬 D4. A variable is empty in the template but defined in group_vars
> A: Precedence shadowing — something stronger defines it (set_fact, include_vars, host_vars, `-e`) or the name has a typo that `default()` swallowed. Bisect with `-e` (always wins) then `ansible-inventory --host` and task-level shadowing to find the layer. **Prevent:** `mandatory` for required inputs.

## 🎬 D5. Handler didn't run but the config changed — production drift risk!
> A: Likely paths: a later task failed before handler phase; `--tags` filtered the handler; host went unreachable. Immediate: run handler-only pass (`--tags` on handler, or targeted restart play) to clear drift. **Prevent:** force_handlers at platform level or critical restarts in `block/always`, tag handlers.

## 🎬 D6. Every run shows `changed` on the same 3 tasks
> A: Nondeterminism: `shell` without `creates`, template with timestamp/random, `state: latest` package drift, dict-order template loops. Fix each with real modules/`changed_when`/deterministic templates. Perma-changed plays hide real regressions — treat as defects.

## 🎬 D7. `--check --diff` looks clean, but the apply breaks
> A: Check-mode blind spots: tasks skipped in check (`command`, API POSTs) or custom modules without check support — the plan lied. Audit with `when: not ansible_check_mode` markers, add check support to custom modules, treat check as indicative not gospel.

## 🎬 D8. Role works standalone (Molecule green), fails in the real playbook
> A: Environment delta: vars overridden by group_vars/role-params collision, missing collections in the prod EE, different facts (real OS vs container), dependencies not in requirements.yml. Reproduce with `-vv`, diff the var resolution (`ansible-inventory --host`), pin the missing dep. Lesson: molecule tests inputs you gave it; prod gives others.

## 🎬 D9. Intermittent `UNREACHABLE` on 2–3 random hosts each run
> A: Flaky network vs host load: correlate with host metrics; check ControlPersist/multiplexing settings, DNS TTLs, and target sshd rate limits (`MaxStartups` drops under burst). Mitigate: connection reuse, retries at platform level (AAP), `wait_for_connection` pre-play for sleepy hosts, fix the stragglers' I/O.

## 🎬 D10. Vault decrypt fails only in CI
> A: Wrong/missing vault password for that vault-id (CI has one file, repo now uses two), or `ANSIBLE_CONFIG` differences (different vault-id labels in header). Reproduce locally with the CI's exact command line. **Prevent:** vault-id naming convention + CI parity checks.

## 🎬 D11. Dynamic inventory shows a host that no longer exists
> A: Cache staleness or filter gap (stopped/deleted instances included). `--flush-cache`, verify filters (`instance-state-name: running`), check cache TTL vs fleet churn. If it recurs: freshness pre-check play that fails on unreachable hosts before real work.

## 🎬 D12. K8s deploy task "succeeds" but pods never update
> A: The apply succeeded but rollout wasn't gated: add `k8s_info` readyReplicas until-loop; also check imagePullPolicy/tag (moving `:latest` tag never pulled), and namespace/context (applied to the wrong cluster!). Gate + verify rollout status as pipeline steps.

## 🎬 D13. Playbook hangs forever at one task, no timeout
> A: Usually an unbounded waiter: `wait_for` without timeout (default waits), a lookup hitting a dead service, or a prompt-hung sudo (`become_pass` missing in non-interactive run). Kill with `-vvv` observation; add explicit `timeout:` everywhere; CI-side job timeouts as backstop.

## 🎬 D14. After enabling pipelining, sudo fails on exactly 12 old hosts
> A: Legacy `requiretty` in their sudoers — pipelining needs non-tty sudo. Fix sudoers (drop requiretty) via a one-off `raw`/`command` play, or exclude those hosts until patched. The lesson: environment heterogeneity is why pipelining is opt-in.
