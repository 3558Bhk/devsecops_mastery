# 08 — Error Handling & Rollbacks (🟢 5 · 🟡 7 · 🔴 6)

> Course ref: [08-error-handling.md](../ansible-mastery/08-error-handling.md)

## 🟢 Basic

**Q1. What does `ignore_errors: true` do, and what's the danger?**
> A: The play continues despite the task failing (host flagged). Danger: silently proceeding with broken state — always pair with `register` + an explicit follow-up decision.

**Q2. What is `failed_when`?**
> A: A custom failure condition overriding the module's default — e.g., HTTP 200 but `"degraded" in body` → fail. You define failure honestly.

**Q3. What does `block/rescue/always` map to?**
> A: try / except / finally. Tasks in `rescue` run on failure inside `block`; `always` runs regardless (cleanup, telemetry).

**Q4. What is `any_errors_fatal`?**
> A: Any single host failure aborts the entire play immediately on all hosts — the fail-fast switch for irrevocable sequences.

**Q5. What's `ignore_unreachable`?**
> A: Host can't be reached (SSH failure) → play continues, host marked unreachable. Without it, unreachable hosts drop out of the batch and fail the run at the end.

## 🟡 Intermediate

**Q6. max_fail_percentage — how does it work with serial?**
> A: Per-batch failure tolerance: with `serial: 10` and `max_fail_percentage: 20`, the play aborts only if >2 of the 10 hosts in the current wave fail. 0 means any failure stops further waves.

**Q7. What do handlers do when the play fails mid-way?**
> A: By default they don't run → config changed but service not restarted = drift. Fix with `force_handlers: true` / `--force-handlers`, or put critical notifications in a `block`'s `always:`.

**Q8. What are `ansible_failed_task` and `ansible_failed_result`?**
> A: Magic vars inside `rescue` naming the failed task and its result — use them so alerts say *what* broke, not just that something did.

**Q9. What happens if a rescue task itself fails?**
> A: The host ends the play as failed even if later rescue tasks succeed — there's no "recovered" marker. That's correct: a failed rollback is a real emergency and should page loudly.

**Q10. Design a rollback for a symlink-based release deploy.**
> A: Before mutating, capture `readlink current` into `previous_release`; in `rescue`: flip symlink back, restart via handler, verify health; `always`: re-enable in LB. You can only roll back to what you recorded — capture first.

**Q11. changed_when vs failed_when — same mechanism, different meaning?**
> A: Both override module reporting: `changed_when` declares whether state mutated (honest reporting → correct handler triggering); `failed_when` declares whether the attempt failed (correct failure semantics).

**Q12. How do you keep a play running when one host fails, but still get a failure summary?**
> A: `ignore_errors` + register per task, then a final `run_once` report play aggregating failures from `hostvars` — fail the report play if any host failed, so CI still goes red.

## 🔴 Advanced

**Q13. Design end-to-end failure handling for a 200-host rolling deploy.**
> A: `serial` canary waves + `max_fail_percentage: 0`; per host block/rescue: drain → deploy (versioned, validated) → health gate → enable, with rescue = rollback-to-captured + verify; `always` re-enables LB; final aggregate report play; alerts carry `ansible_failed_task` context.

**Q14. What are the limits of rescue (what does NOT trigger it)?**
> A: Unreachable hosts (they skip, not fail into rescue), handler failures after the block, parse/syntax errors, and `meta:` runtime errors. Rescue is for task failures inside its block — that's why connectivity pre-checks and validated syntax matter upstream.

**Q15. How do you make a crashed mid-deploy playbook safely resumable?**
> A: Idempotent everywhere, `creates:` guards, atomic symlink flips, no direct restarts outside handlers, pre_tasks that detect half-applied state (dir exists but symlink stale) and reconcile — re-run converges instead of redoing.

**Q16. A `--force-handlers` run restarted services despite failure — is that good?**
> A: It prevents drift (config applied + service reloaded) but can restart onto a broken stack. Judgment: force-handlers for config-only changes; for risky deploys prefer explicit `always:` sections with health verification, not blanket force.

**Q17. How would you implement "abort the fleet if the canary error rate rises"?**
> A: Per-wave metrics gate: after canary wave, `run_once` task queries Prometheus/monitoring API, `failed_when` on error-rate threshold — wave failure stops further batches (serial semantics), leaving exposure limited to the canary.

**Q18. What's your incident response when your own automation caused a partial outage?**
> A: Stop scheduling (abort run), assess blast radius via recap/logs, roll back affected waves (rollback play), verify through user-visible endpoints, then post-mortem the playbook (missing health gate? bad validate?) and add the missing guard as a regression test.
