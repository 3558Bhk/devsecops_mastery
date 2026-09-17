# 17 — Interview Cheat Sheet (Rapid-Fire Revision)

> ⏱️ **Time to complete: ~1.5 hrs first pass** — then 20 min per revision rep (aim for: all 55 answers in under 20 min, no notes)
> 📦 **Covers:** 55 rapid-fire Q&A across every topic · whiteboard-ready comparison tables · the precedence card · junior-vs-SDE-3 language · questions to ask THEM · the 2-week sprint plan

> Use this the night before. Every answer ≤ 3 sentences. If any answer doesn't immediately ring true, go back to the referenced file.

---

## A. Architecture & Core (file 01)

1. **Is Ansible agentless? How does it execute?** Push over SSH; module zip → temp dir → python + JSON args → JSON result → cleanup. Nothing installed on targets.
2. **What is idempotency and why is it sacred?** Same run = same result; re-runs report `ok` not `changed`. Enables safe convergence, re-runs after crashes, drift detection, honest reports.
3. **Push vs pull?** Ansible pushes from control node. Puppet/Chef agents pull & self-heal. `ansible-pull` inverts Ansible for huge/edge fleets.
4. **What does a managed node require?** SSH + Python (most modules). `raw`/`script` for pre-Python bootstrap.
5. **ansible vs ansible-core?** core = engine + builtin modules; `ansible` = core + curated community collections.
6. **Config file precedence?** `$ANSIBLE_CONFIG` → `./ansible.cfg` → `~/.ansible.cfg` → `/etc/ansible/ansible.cfg`. `ansible --version` reveals the active one.
7. **Declarative or procedural?** Modules are declarative (diff desired vs actual); play order is procedural; `shell` is the imperative escape hatch.

## B. Inventory (file 02)

8. **`web:&prod:!canary`?** web group ∩ prod group − canary. Union `:`, intersect `:&`, exclude `:!`.
9. **group_vars resolution?** `group_vars/<group>.yml` next to inventory or playbook; playbook-adjacent wins; host beats group; child group beats parent.
10. **Static vs dynamic inventory?** Static = files in git. Dynamic = inventory **plugin** queries a source of truth (AWS tags → groups) at run time; cacheable.
11. **How do you reach hosts behind a bastion?** `ansible_ssh_common_args='-o ProxyJump=bastion'` per host/group.
12. **`--list-hosts` why religiously?** Blast radius before every run. Senior habit, say it out loud.

## C. Playbooks (files 03–05)

13. **When do handlers run?** End of play, deduplicated, only if a notifying task changed. `meta: flush_handlers` forces mid-play; `--force-handlers` runs them even after failures.
14. **`register` gives what?** Result object: `.rc/.stdout/.changed/.failed`, `.stat.*`, `.status`, `.results[]` for loops.
15. **`command` vs `shell` vs `raw`?** command: no shell features (safe default); shell: pipes/globs; raw: no Python needed (bootstrap only).
16. **Fix perpetual `changed` on a command task?** Real module, or `creates:`/`removes:`, or `changed_when:`; read-only probes `changed_when: false`.
17. **`when` + `loop`?** Evaluated **per item** with `item` bound.
18. **import vs include?** import = parse-time/static (`--list-tasks` sees children, `when`/tags stamp all children, no loops). include = runtime/dynamic (loops, computed filenames, `when` evaluated once).
19. **`delegate_to` semantics?** Module runs on the delegated host; facts/vars still from the original host (`delegate_facts: true` to change); `local_action` = delegate to controller.
20. **`run_once`?** First host of the batch executes; others get results; pair with `delegate_to` for cluster-wide one-shots.
21. **`until/retries/delay`?** Poll-until-success retry wrapper — my standard guard for boot/flaky dependencies.

## D. Variables (file 04 — the anchor points)

22. **Precedence, the short form?** `-e` **always wins** → set_fact/registered → include_vars → task > block > role vars > vars_files > play vars > facts > host_vars > group_vars > inventory > **role defaults (lowest)**.
23. **`set_fact` scope?** Host-scoped, runtime, near-top precedence (never for config knobs — derived values only). `cacheable: true` persists to fact cache.
24. **Cross-host variable?** `hostvars['host']['var']`, `groups['web']` — there is no global namespace; vars are per-host.
25. **Magic vars?** `inventory_hostname`, `group_names`, `groups`, `hostvars`, `ansible_play_hosts_all`, `omit`.
26. **Custom facts?** `/etc/ansible/facts.d/*.fact` → `ansible_local.*` — turns node state into inventory-queryable facts.
27. **YAML type gotcha?** `1.10` is a float → quote versions; `yes/no/on/off` are booleans.

## E. Templates (file 06)

28. **`validate:` why non-negotiable?** Renders to temp file, runs a check (`nginx -t -c %s`), fails before the bad config lands. Prevents restart-into-outage.
29. **lookup vs filter vs test?** Lookup fetches external data on the **control node** (`lookup('file'...)`); filter transforms (`| upper`); test predicates (`is defined`).
30. **lookup vs query?** `lookup` stringifies/joins multiple results; `query`/`q` returns a list. Use `query` for multi-value.
31. **`default('x', true)` vs `default('x')`?** The `true` also replaces `false`/empty — otherwise empty strings slip through.
32. **`mandatory`?** Filter that fails loudly on undefined — policy for required inputs instead of silent-empty renders.

## F. Roles & Collections (file 07)

33. **Role tree?** tasks/ handlers/ defaults/ vars/ files/ templates/ meta/ library/.
34. **defaults vs vars?** defaults = lowest precedence, public knobs; vars = high precedence, internal constants.
35. **Role dependency behavior?** `meta/main.yml` `dependencies:` run before parent, in order; `allow_duplicates` for re-runs; can pass vars/when per dep.
36. **requirements.yml?** Pinned roles + collections (semver — never floating in prod); `ansible-galaxy install -r requirements.yml`.
37. **FQCN why?** Unambiguous, grep-able, lint-enforced (`ansible.builtin.copy` vs bare `copy` colliding across collections).

## G. Error Handling (file 08)

38. **block/rescue/always = ?** try/except/finally. Rescue runs on task failure inside block; always runs regardless (cleanup/telemetry). Rescue failure = host failed.
39. **`failed_when` vs `ignore_errors`?** failed_when defines failure honestly; ignore_errors skips handling — only with register + follow-up decision.
40. **Rolling abort control?** `serial` waves + `max_fail_percentage` (per batch) + `any_errors_fatal`.
41. **Rollback design?** Capture previous state before mutating (readlink current release), rescue restores + verifies, `always` re-enables LB/telemetry.

## H. Vault & Secrets (file 09)

42. **Vault cipher/mechanics?** AES256, PBKDF2 from password; decrypts only on control node; header carries vault-id.
43. **vault-id pattern?** `--vault-id prod@prompt|file`; per-env passwords; `vars.yml` (plaintext names) → `vault.yml` (encrypted `vault_*` values).
44. **`no_log: true`?** Suppresses task output AND rendered args — mandatory wherever secrets hit command lines/templates.
45. **Better than Vault?** External lookups (HashiCorp Vault, AWS SSM/Secrets Manager) — TTL, rotation, audit; Ansible holds no long-lived secrets.

## I. Deploys, Performance, Scale (files 10–11)

46. **Zero-downtime deploy in one sentence?** `serial` waves × per-host: drain from LB → deploy versioned release (symlink flip) → health-check gate → re-enable; block/rescue rollback; max_fail_percentage 0.
47. **Canary in Ansible?** `serial: [1, 5, "25%"]` — one host, small batch, quarter, rest; abort on first bad wave.
48. **`forks` vs `serial` vs `throttle`?** Global parallel budget / per-play batch (blast radius) / per-task cap.
49. **`strategy: free` when?** Hosts independent, no cross-host ordering; breaks orchestration semantics — know when NOT to.
50. **Async use case?** Long tasks (`poll: 0`) free fork slots; you own polling via `async_status`; not all modules support it.
51. **pipelining?** Streams modules over SSH stdin instead of SFTP — kills a transfer per task; off by default for legacy `requiretty`; first tuning knob.
52. **Fact caching?** `gathering: smart` + jsonfile/redis cache plugin → facts fetched once per TTL, not per run; `--flush-cache` on inventory churn.
53. **Tune a slow playbook — order of attack?** Measure (profile_tasks/timer) → pipelining + ControlPersist → forks → skip/subset/cache facts → strategy/async → task design (fewer, native modules).
54. **add_host pattern?** Provision play registers new instance into in-memory group; next play targets that group — same-run provisioning.
55. **Terraform vs Ansible?** Terraform provisions/owns lifecycle with state + plan; Ansible configures/orchestrates in place, stateless. Terraform owns birth→death; Ansible owns everything inside.

---

## The comparison tables (whiteboard-ready)

| | **Ansible** | **Terraform** | **Puppet/Chef** | **Salt** |
|---|---|---|---|---|
| Model | push, agentless, YAML | plan/apply, state file | agent pull daemons | push/pull hybrid |
| State | none (live diff) | central state file | agent-side | master-side |
| Sweet spot | config mgmt, orchestration, app deploys | infra provisioning | continuous convergence | scale + speed |
| Mutation | in-place converge | create/destroy/recreate | in-place | in-place |

| | **import** | **include** |
|---|---|---|
| Resolved | parse time | runtime |
| `--list-tasks` | shows children | one line |
| loop-able | ❌ | ✅ |
| `when` on statement | stamped on all children | evaluated once |

| **Precedence (short)** | |
|---|---|
| 🥇 `-e` extra vars | always wins |
| `set_fact` / registered | runtime |
| task > block > role vars > vars_files > play vars | static, closer = stronger |
| host_vars > group_vars > inventory | specificity |
| 🥉 role defaults | weakest |

---

## The SDE-3 difference (what to embody in every answer)

| Junior says | SDE-3 says |
|---|---|
| "I write playbooks" | "I design automation with bounded blast radius and automated verification" |
| `shell` + curl | proper modules; `shell` only with `changed_when` + justification |
| "it works" | "second run reports changed=0; canary wave verified through LB; rollback tested" |
| plain vars in git | Vault-encrypted or external lookups; `no_log` on secrets path |
| one big playbook | thin orchestrator + data-driven roles + env in inventory |
| "we run it manually" | "lint → check/diff → staging → approval gate → prod, all in CI/AAP with audit trail" |

**The five words to weave in:** *idempotency, blast radius, rollback, observability, convergence.*

---

## Questions to ask THEM (signals of seniority)

- "How many hosts/environments, and static or dynamic inventory today?"
- "Where does Terraform end and Ansible begin in your org?"
- "How do you handle secrets — Vault files in git or an external manager?"
- "What's your deploy strategy — rolling, blue-green, GitOps?"
- "Is there a self-service layer (AWX/AAP), or CLI-driven CI?"
- "How do you test roles — Molecule, staging-first, canary waves?"

*(Asking about their automation maturity = you've operated at scale. That impression is worth more than one more fact recalled.)*

---

## 2-week sprint plan (if interview is soon)

| Days | Focus | Files |
|---|---|---|
| 1–2 | Lab + fundamentals + inventory | 01, 02 |
| 3–4 | Playbooks, variables, precedence drills | 03, 04 |
| 5 | Control flow, templates | 05, 06 |
| 6–7 | Roles, error handling, vault | 07, 08, 09 |
| 8 | Rolling deploys + performance (write the zero-downtime play from memory!) | 10, 11 |
| 9–10 | Cloud, containers, CI/CD | 12, 13 |
| 11 | Custom modules + Molecule (write one of each) | 14 |
| 12 | AWX/AAP + Cookbook projects | 15, 16 |
| 13–14 | Cheat sheet reps + mock interviews (record yourself explaining Project 2 & 6) | 17 |

Good luck — you're walking in with production-grade patterns, not syntax trivia. 🚀
