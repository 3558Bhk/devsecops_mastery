# 03 — Playbooks & Modules (🟢 8 · 🟡 9 · 🔴 7)

> Course ref: [03-playbook-basics.md](../ansible-mastery/03-playbook-basics.md)

## 🟢 Basic

**Q1. What's the difference between a play and a playbook?**
> A: A play maps an ordered task list to a set of hosts with shared scope (become, vars, serial). A playbook is the YAML file containing one or more plays — the unit you execute.

**Q2. What is `become`?**
> A: Privilege escalation on the target (default via sudo). Set per play/task (`become: true`, `become_user:`), or behaviorally via `ansible_become*` inventory vars.

**Q3. Name five modules you use daily.**
> A: `apt/dnf/package`, `service`, `copy`, `template`, `file` — plus `lineinfile`, `get_url`, `unarchive`, `uri`, `user` covers ~80% of daily work.

**Q4. What does `register` do?**
> A: Captures a task's result object into a variable — `.rc`, `.stdout`, `.changed`, `.failed`, `.stat.*`, `.status`, or `.results[]` when the task loops — enabling conditionals and debugging.

**Q5. What is a handler?**
> A: A task triggered by `notify` that runs at the **end of the play**, deduplicated, and only if a notifying task actually changed something — the classic "restart service once after many config changes."

**Q6. What does `state: present` vs `state: latest` mean for packages?**
> A: `present` installs only if missing (stable re-runs); `latest` upgrades whenever a newer version exists (reports changed on upgrades, can surprise you in CI).

**Q7. How do you copy a file with different content per host?**
> A: `template` with Jinja2 (vars/facts render per host), or `copy` with `content: "… {{ inventory_hostname }} …"` for short dynamic content.

**Q8. What's `--syntax-check` vs `--check`?**
> A: Syntax check only parses YAML/task structure (fast, no host contact). `--check` is a full dry-run against real hosts with module-level simulation; add `--diff` to see would-be file changes.

## 🟡 Intermediate

**Q9. Order of execution within a play?**
> A: `pre_tasks` → `roles` → `tasks` → `post_tasks` → notified handlers (at the end, deduplicated). `meta: flush_handlers` runs pending handlers immediately at that point.

**Q10. How do you make a `command` task idempotent?**
> A: Real module first; else `creates:`/`removes:` guards, or `changed_when: <honest condition>` (e.g., parse output). Read-only probes get `changed_when: false`.

**Q11. Why `validate:` on config file tasks — what's the mechanism?**
> A: The module writes to a temp file, runs your command with `%s` as the temp path (`nginx -t -c %s`, `visudo -cf %s`), and only moves the file into place if validation passes — a bad config never lands and never triggers a restart.

**Q12. What does `meta: flush_handlers` solve?**
> A: Handler-at-end semantics: after a config change you often must restart + health-check **before** subsequent tasks. Flush runs notified handlers right there, in the middle of the play.

**Q13. How do `wait_for` and `until/retries/delay` differ?**
> A: `wait_for` is a purpose-built waiter (port/file/path/drained). `until/retries/delay` is a generic poll-until-success wrapper around any task result — my standard guard for boots and flaky dependencies.

**Q14. What fields does a `uri` result give you, and how do you health-check with it?**
> A: `.status`, `.json`, `.body`… Health check: `status_code: 200`, `register` + `until: result.status == 200`, `retries`, `delay`, and `changed_when: false` so GETs stay clean.

**Q15. Multi-play playbooks — why split instead of one play with groups?**
> A: Each play re-targets, resets scope (become/facts/serial), and sequences dependencies: quiesce apps → migrate DB once → roll apps back up. Orchestration ordering lives between plays, not inside one play.

**Q16. How do you pass different values per host group in one play?**
> A: Group vars (or conditional ternaries): `max_conn: "{{ 500 if 'prod' in group_names else 100 }}"` — prefer env-in-inventory so tasks stay branch-free.

**Q17. `--start-at-task` and `--step` — when are they safe?**
> A: On **idempotent** playbooks. They skip earlier state setup, which is only safe if re-running the whole play converges anyway — that's exactly why idempotency is sacred.

## 🔴 Advanced

**Q18. A handler didn't run despite its task changing. Enumerate causes.**
> A: (1) A later task failed → play aborted before handler phase (use `--force-handlers`/`block always`); (2) run was filtered by `--tags` and the handler wasn't tagged; (3) host became unreachable mid-play; (4) the handler was notified but the notifying task was skipped in check mode; (5) flush didn't happen and the play ended in another play's failure context.

**Q19. Design the structure of a release-deploy play for auditability and rollback.**
> A: Capture previous state first (`readlink current`), versioned release dirs + atomic symlink flip, `validate` on config, handler restart + `flush_handlers`, health gate with retries, rescue-rollback to captured path, `always` re-enable in LB; everything named, no secrets in logs, summary registered for a final report play.

**Q20. Why is `state: restarted` in the main service task an anti-pattern?**
> A: It restarts on EVERY run even when nothing changed — downtime without cause, spurious changed counts, unnecessary drain windows. Correct pattern: `started` + `enabled` in the task; restarts only via notified handlers.

**Q21. What breaks under `--check` in a real playbook, and how do you handle it?**
> A: Tasks with external side effects (`command`, `uri POST`, service restarts) can't simulate — they're skipped, giving a false-green plan. Handle with `check_mode: false` only where truly safe, `when: not ansible_check_mode` for destructive bits, and treat check output as indicative, not gospel.

**Q22. Explain loop + register result structure and a safe iteration pattern over failures.**
> A: Registered loop results live under `.results[]`, each with its own `.item/.rc/.failed`. Pattern: second task loops `result.results`, `when: item is failed` — e.g., collect failed items into a report or retry list. Direct `result.stdout` access crashes with "no attribute stdout".

**Q23. How do you enforce "this playbook must be verifiable" as a team standard?**
> A: ansible-lint in CI (blocks `shell` soup, missing `changed_when`, unnamed tasks), Molecule idempotence step per role, mandatory `--check --diff` artifact in pipelines, code review checklist: validate/handlers/health-check/serial present.

**Q24. What is the difference between `listen:` handlers and plain handlers, and when does it pay off?**
> A: `listen` creates named topics multiple handlers subscribe to — one `notify: "deploy app"` triggers restart + cache-warm + LB-check together. Pays off when several components react to the same event, decoupling tasks from handler names.
