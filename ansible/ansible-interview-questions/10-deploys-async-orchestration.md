# 10 — Deploys, Async & Orchestration (🟢 5 · 🟡 8 · 🔴 7)

> Course ref: [10-rolling-deploys-async.md](../ansible-mastery/10-rolling-deploys-async.md) · [08-error-handling.md](../ansible-mastery/08-error-handling.md)

## 🟢 Basic

**Q1. What does `serial` do?**
> A: Batches a play's hosts: `serial: 5` runs 5 hosts fully through the play before the next 5 — bounding blast radius. Accepts percentages and lists (`serial: [1, 5, "25%"]`).

**Q2. What is `forks`?**
> A: The global parallelism budget — how many hosts are worked simultaneously (default 5). Config (`forks =`) or `-f`. Distinct concern from serial (batch size vs parallelism).

**Q3. What are the default and alternative strategies?**
> A: `linear` (default: all hosts sync per task), `free` (hosts rush independently), `host_pinned` (per-host sequential, capacity-limited).

**Q4. What does `async: 300, poll: 0` mean?**
> A: Start the task and return immediately (fire-and-forget) with a 300 s runtime allowance; track later via `async_status` with the returned job id. `poll: 0` is what makes it non-blocking.

**Q5. What does the `reboot` module do?**
> A: Initiates reboot, drops the connection, waits for the host to come back, and re-establishes connectivity (with `reboot_timeout`, `test_command`) — far safer than a `shell: shutdown -r` hack.

## 🟡 Intermediate

**Q6. Explain the zero-downtime deploy cycle per host.**
> A: Drain from LB → wait connections drained → versioned release + symlink flip → handler restart → local health check (`until/retries`) → re-enable in LB. Play-level: canary `serial` waves + `max_fail_percentage: 0` + block/rescue rollback.

**Q7. How do you express a canary deployment in Ansible?**
> A: `serial: [1, 5, "25%"]` — one host, then small batch, then quarter, then rest — with `any_errors_fatal`/max_fail so a bad canary wave stops the rollout automatically.

**Q8. Rolling vs blue-green — how do you choose?**
> A: Rolling: gradual exposure, no extra capacity, slower full-fleet validation. Blue-green: full-stack verification before cutover + instant rollback, costs 2× capacity and needs backward-compatible migrations. Choose by blast-radius tolerance and infra cost.

**Q9. What is `throttle` and when do you use it?**
> A: Per-task concurrency cap — e.g., a task hitting a licensed vendor tool or fragile shared DB. `throttle: 4` runs at most 4 simultaneous executions regardless of forks.

**Q10. Async caveats?**
> A: Not all modules support it; handlers can't be async; fire-and-forget = you own polling (`async_status`), and an un-reaped job after connection loss leaves an orphan — re-runs must reconcile.

**Q11. Why re-gather facts after a reboot?**
> A: Facts were collected at play start — pre-reboot data. Asserting kernel version post-reboot without `setup` re-run validates the *old* state; classic subtle bug.

**Q12. How do you orchestrate through a load balancer with Ansible primitives?**
> A: `delegate_to` the LB host (or its API) while looping over web hosts: disable member → deploy → verify → enable member; `hostvars[groups['lb'][0]]` for its address; `wait_for: state: drained` for graceful connection drain.

## 🔴 Advanced

**Q13. "Deploy v2 to 200 servers, zero downtime, auto-rollback" — 60-second architecture.**
> A: CI passes `-e release=…`; play: `serial: [1,5,25%]`, per-host drain (LB API via delegate_to) → wait drained → release dir + atomic symlink flip (validate config) → flush handlers → health gate with retries → re-enable; rescue rolls back to captured previous release and re-verifies; `always` re-enables LB; `max_fail_percentage: 0` halts on first bad wave; final aggregate report + Slack.

**Q14. Where does Ansible's linear model fall short for orchestrations, and what are the workarounds?**
> A: No global transaction/barrier across heterogeneous steps; per-host failure mid-wave affects only its batch. Workarounds: multi-play sequencing (each play = a global phase), `run_once` gates, metrics-gate tasks between waves, `any_errors_fatal` for irrevocable steps.

**Q15. How would you run a 45-minute job on 100 hosts without holding 100 connections?**
> A: `async: 2700, poll: 0` to launch, do other work, then a second task polling `async_status` with `until: finished, retries, delay` — or fire-and-forget plus a separate verification play. Frees forks/connections during the wait.

**Q16. Blue-green: what's the trap with database schema changes?**
> A: Both colors run simultaneously → migrations must be backward-compatible (expand/contract): add nullable columns/tables first, deploy both colors, backfill, then contract in a later release. Saying "expand/contract" is the senior tell.

**Q17. Design the LB flip for blue-green and justify its blast radius.**
> A: One templated pool config on the LB with `validate: haproxy -c` (or nginx -t) + reload — atomic, single-file change; rollback = re-render previous color. The *deploy* touches a fleet; the *cutover* touches one file — minimize the mutation that changes user-visible state.

**Q18. How do you make deploys idempotent when the artifact store is eventually-consistent?**
> A: Pin artifacts by checksum (`get_url checksum: sha256:…`), versioned release dirs with `creates:`, verify artifact integrity before symlink flip; never deploy `latest` tags — immutable versioned artifacts only.

**Q19. What's your strategy for a fleet where 5% of hosts are chronically slow/failing?**
> A: Exclude them from main waves (inventory group `unhealthy`), dedicated remediation play, `strategy: free` for heterogeneous speeds, `max_fail_percentage` tuned so chronic stragglers don't block the healthy 95% — plus fixing root cause, not just rerunning.

**Q20. How does ansible-pull change the deployment model, and when is it the right call?**
> A: Nodes cron-pull their playbook from git and run locally (`connection: local`) — infinite horizontal scale, self-healing cadence, edge-friendly. Costs: no central orchestration (`delegate_to`, `run_once`, cross-host ordering), eventual consistency, and per-node secrets handling.
