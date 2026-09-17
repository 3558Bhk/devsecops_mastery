# 05 — Conditionals, Loops, Tags & Import/Include (🟢 6 · 🟡 8 · 🔴 6)

> Course ref: [05-control-flow.md](../ansible-mastery/05-control-flow.md)

## 🟢 Basic

**Q1. How does `when` work?**
> A: A per-task (or per-block) condition evaluated as a bare Jinja expression — no `{{ }}`. False → task skipped. With loops it's evaluated once per item.

**Q2. Write a condition: run only on Ubuntu 22+.**
> A: `when: ansible_facts['distribution'] == "Ubuntu" and ansible_facts['distribution_version'] is version('22.04', '>=')`.

**Q3. How do you loop over a list? A dict?**
> A: List: `loop: "{{ packages }}"` using `{{ item }}`. Dict: `loop: "{{ users | dict2items }}"` using `item.key`/`item.value`.

**Q4. What are tags for?**
> A: Selecting task subsets at run time: `--tags config`, `--skip-tags slow`. Tasks can carry multiple tags; `always`/`never` have special semantics.

**Q5. import vs include in one sentence each.**
> A: `import_*` is processed at parse time (static — task list known upfront). `include_*` is processed at run time (dynamic — computed files, loops, one-shot `when`).

**Q6. What does `delegate_to` do?**
> A: Runs the module on a different host than the play target (e.g., talk to the LB while looping over web hosts); vars/facts still come from the original host unless `delegate_facts: true`.

## 🟡 Intermediate

**Q7. `when` + `loop`: how many evaluations?**
> A: Once per item with `item` bound. To skip the whole loop, filter the list upstream (`selectattr`) or put `when` on an `include_tasks` wrapper.

**Q8. Tags + handlers gotcha?**
> A: `--tags config` also filters handlers — an untagged handler won't run even though its notify fired. Tag handlers too, or run the full play.

**Q9. Why can't `import_tasks` be looped?**
> A: Imports resolve at parse time — before any loop executes. Runtime looping of task files requires the dynamic `include_tasks` (each iteration loads the file when reached).

**Q10. What happens to tags on an `import_tasks` statement?**
> A: They're stamped onto every imported child task. On `include_tasks`, they only gate the include itself — a subtle difference interviewers use to catch rote learners.

**Q11. What does `until`/`retries`/`delay` actually count?**
> A: `retries` is total attempts (not extra tries); `delay` sleeps between attempts; failure only after the last attempt fails. My default guard for service boots and flaky endpoints.

**Q12. `run_once: true` — which host runs it, and what do the others get?**
> A: The first host of the current batch executes; the others are marked skipped but the result is visible via `hostvars[first_host]`. Pair with `delegate_to` for a specific executor.

**Q13. `strategy: free` — what breaks?**
> A: Cross-host ordering: "everyone stopped before migration" no longer holds since each host rushes independently. Use only when tasks are host-local and independent; orchestration plays stay `linear`.

**Q14. What's `loop_control` useful for?**
> A: `label` (readable logs — keep secrets out), `index_var` (position), `pause` (rate limiting between iterations), `loop_var` (avoid clobbering nested `item`).

## 🔴 Advanced

**Q15. import vs include across `--list-tasks`, `when`, tags, and loops — full matrix.**
> A: import: children visible in `--list-tasks`, `when`/tags stamped on all children, no loops. include: appears as one line, `when` evaluated once for the decision, tags gate only the include, loops supported. Default to import; include for runtime decisions.

**Q16. Pattern: run a migration once while an app tier of 50 is quiesced.**
> A: Three plays — play 1 stops apps (or `serial: 100%`), play 2 targets `db[0]` with the migration (`changed_when` on output), play 3 restarts apps with `serial` + health checks. Never one play with `free` — per-host ordering can't express global sequencing.

**Q17. You need "task X on all hosts must finish before task Y starts on any host" — default strategy guarantees this? What weakens it?**
> A: Yes — `linear` syncs all hosts at each task boundary. It's weakened by `strategy: free`, async fire-and-forget (no barrier), or per-host failures removing hosts from the batch.

**Q18. Design rate-limited task execution against a fragile shared API.**
> A: `throttle: N` caps concurrent executions of that task; combined with `until/retries` and `loop_control.pause` for spacing; optionally `async` so the fleet isn't serialized while a few hammer the API.

**Q19. What's the difference between skipping and failing-fast design, and how do you implement fail-fast fleet-wide?**
> A: Skipping (`when`) is per-host flow control; fail-fast is global protection: `any_errors_fatal: true` aborts everything on first failure, `max_fail_percentage: N` allows bounded failures per serial batch before aborting further waves.

**Q20. When do you reach for `include_role` over the `roles:` section?**
> A: When role application itself is dynamic: conditional per host, inside loops (per tenant/instance), or ordering role application between plain tasks mid-play — the `roles:` section is static, play-scoped, and runs before `tasks:`.
