# 14 — Custom Modules, Plugins & Testing (🟢 4 · 🟡 6 · 🔴 6)

> Course ref: [14-custom-plugins-testing.md](../ansible-mastery/14-custom-plugins-testing.md)

## 🟢 Basic

**Q1. When do you write a custom module?**
> A: Only when no existing module covers it (internal API/proprietary appliance) and `uri`+`failed_when` composition isn't enough — custom code is maintenance debt; exhaust the ecosystem first.

**Q2. What is the module "contract"?**
> A: Consume JSON args, print exactly one JSON result to stdout via `exit_json`/`fail_json` (with `changed`/`failed` flags) — nothing else may write to stdout.

**Q3. What is AnsibleModule and what does it buy?**
> A: The helper class handling argument parsing, type/choice/required validation, check-mode plumbing, and JSON exit paths — you never parse argv yourself.

**Q4. Name Ansible's testing layers.**
> A: yamllint/ansible-lint (static), `--syntax-check`, `--check --diff` against staging, Molecule for roles (behavior + idempotence in disposable containers), canary waves in prod.

## 🟡 Intermediate

**Q5. Where can a custom module live?**
> A: `library/` beside a playbook (auto-loaded), `library/` inside a role (role-scoped), or properly packaged in a collection's `plugins/modules/` for org-wide reuse.

**Q6. What do DOCUMENTATION/EXAMPLES/RETURN strings do?**
> A: Machine-readable docs — `ansible-doc` renders them, `ansible-test sanity` validates them; they're what makes a module reviewable and usable by others. Skipping them fails CI in serious shops.

**Q7. What does `supports_check_mode` require of your code?**
> A: You honor `module.check_mode`: report what *would* change without side effects. Without support, `--check` skips your module (false plans) — or worse, a careless module mutates during dry-runs.

**Q8. Filter vs lookup vs callback plugin — one line each.**
> A: Filter: transform a value in Jinja (`| cidr_host`). Lookup: fetch external data at control-node time (`lookup('itsm', …)`). Callback: hook run lifecycle for output/notifications/metrics.

**Q9. What is Molecule's idempotence step?**
> A: It runs the converge play **twice** and fails if the second run reports `changed > 0` — automated enforcement of Ansible's core promise, per role, in CI.

**Q10. Molecule vs staging testing?**
> A: Molecule: hermetic, disposable, per-role behavior tests with exact inputs across platform matrices, minutes per run. Staging: real integration (LB/DNS/shared services), but shared/stateful/slow. Both — they answer different questions.

## 🔴 Advanced

**Q11. Sketch a production-grade custom module for an internal REST API.**
> A: `AnsibleModule` with full argument_spec (types, choices, required_if), check-mode returning would-be diff, idempotent: GET current state → compare → POST/PUT only on diff → return `changed` + new state; document; unit-test state-comparison logic; ship via internal collection; `no_log` on token-bearing args.

**Q12. Why is a `shell`+curl "quick fix" worse than a module for the same integration?**
> A: No idempotency (always changed → handler storms), no check mode, no argument validation, secrets visible in command lines/logs, and logic trapped in YAML strings — unmaintainable and unauditable. The module centralizes semantics once.

**Q13. How do you distribute internal plugins/roles across many repos?**
> A: Internal collection, semver-tagged, in requirements.yml pins (or private automation hub); loose top-level `filter_plugins/` dirs die at repo #4. Versioned distribution + lint gates = shared code that doesn't rot.

**Q14. Design the CI for a shared role repo.**
> A: PR: yamllint + ansible-lint (production profile) → Molecule test matrix (Ubuntu/Rocky) incl. idempotence → sanity tests if in collection → integration job against a staging compose env for select changes → merge blocks on all red. Version tag job publishes the collection artifact.

**Q15. What sanity traps bite custom code?**
> A: `print()` polluting stdout (breaks JSON contract), missing check-mode support, Python 2/3 or interpreter assumptions, unvalidated args (KeyError at 3 a.m.), and swallowing exceptions without `fail_json` context — all caught by sanity tests + review checklist.

**Q16. When is a callback plugin the right architecture choice (vs a playbook task)?**
> A: Cross-cutting concerns that must apply to EVERY run without play authors remembering: metrics emission, failure notifications, centralized audit logging. If it's per-workflow logic it belongs in tasks; if it's platform policy it belongs in a callback (or AAP notifications).
