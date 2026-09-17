# 📇 INDEX — Every File, Its Topics & Time

> The complete map of this repo in one page. Open the file you need, or follow the learning path top to bottom.
> **Total course: ≈ 40 hours** · **Interview-crash path: see "Fast routes" below** · **Last-minute: file 18 (45/30/10 min)**

---

## 🗂️ Master Index

| # | File | Topics it covers | ⏱️ Time |
|---|------|------------------|---------|
| — | [Root README](README.md) | Repo guide, study method, total time budget, lab setup (Vagrant/Docker), how interviews test Ansible | 45 min |
| 00 | [Playbook Writing Guide](00-playbook-writing-guide.md) | **Step-by-step ladder to master playbook writing** — 12 graded steps from first `ping` play to a zero-downtime deploy from memory, with exercises & checkpoints | ~14 h (overlaps files 01–10) |
| 01 | [Fundamentals](01-fundamentals.md) | Agentless push model · module execution over SSH (AnsiballZ) · idempotency & `changed` · ansible vs ansible-core · ansible.cfg & config precedence · facts · ad-hoc · first playbook with handlers · declarative vs procedural | ~2.5 h |
| 02 | [Inventory & Ad-hoc](02-inventory-adhoc.md) | INI/YAML inventories · groups & groups-of-groups · ansible_host/ProxyJump vars · targeting patterns & `--limit` · group_vars/host_vars layout · command vs shell vs raw vs script · bootstrap scenario · dynamic inventory intro | ~1.5 h |
| 03 | [Playbook Basics](03-playbook-basics.md) | Play anatomy & execution order · 12 everyday modules · register & result objects · handler semantics · the full production app-release playbook · --check/--diff workflow · multi-play orchestration · verification tasks | ~2.5 h |
| 04 | [Variables & Facts](04-variables-facts.md) | Variable families · **precedence ladder + proof lab** · facts & gather_subset · custom facts (ansible_local) · magic vars (hostvars, groups, omit) · set_fact & cacheable facts · cross-host data · multi-env repo layout · debugging var soup | ~2 h |
| 05 | [Control Flow](05-control-flow.md) | `when` & tests · loops & dict2items & loop_control · until/retries/delay · tags & the handler gotcha · **import vs include** · delegate_to / run_once / local_action · LB-orchestrated rolling play | ~2 h |
| 06 | [Jinja2 Templates](06-jinja2-templates.md) | template + validate · filter toolbox (defaults, collection surgery, crypto, time, ternary) · tests · lookup vs query · fleet-wide /etc/hosts from inventory · env-aware configs (mandatory, no_log) · escaping & gotchas | ~2.5 h |
| 07 | [Roles & Collections](07-roles-collections.md) | Role anatomy · build a data-driven nginx role · defaults vs vars · role params · meta & dependencies · collections, FQCN, requirements.yml pinning · mature repo layout · one-role-many-topologies | ~2.5 h |
| 08 | [Error Handling](08-error-handling.md) | failed_when / changed_when / ignore_errors done right · any_errors_fatal & max_fail_percentage · block/rescue/always + ansible_failed_task · **full zero-downtime deploy with auto-rollback** · force_handlers · rollback design | ~2 h |
| 09 | [Vault & Secrets](09-vault-secrets.md) | Vault CLI (create/edit/view/rekey/encrypt_string) · vault-ids, per-env passwords · vars.yml→vault.yml pattern · no_log · external managers (HashiCorp Vault, SSM) · CI integration · leaked-secret response | ~1.5 h |
| 10 | [Rolling Deploys & Async](10-rolling-deploys-async.md) | forks vs strategy vs serial vs throttle · linear/free/host_pinned · canary waves · **zero-downtime LB deploy playbook** · blue-green trade-offs · async/poll/async_status · reboot-and-verify · stale-facts trap | ~3 h |
| 11 | [Performance Tuning](11-performance-tuning.md) | profile_tasks/timer · pipelining & ControlPersist · forks sizing · fact caching · strategy/async/throttle wins · task design · 40-min→8-min case study · ansible-pull & scale-out | ~1.5 h |
| 12 | [Cloud & Dynamic Inventory](12-cloud-dynamic-inventory.md) | aws_ec2 plugin (filters, keyed_groups, compose, cache) · EC2 provisioning + add_host pattern · Route53/SG/S3 modules · idempotency vs provider APIs · **Ansible↔Terraform boundary** | ~2 h |
| 13 | [Docker, K8s & CI/CD](13-docker-k8s-cicd.md) | docker_image/container/compose_v2 · kubernetes.core & rollout gates · Ansible vs GitOps (Argo/Flux) · CI pipeline (lint→check→staging→prod) in GitHub Actions/GitLab · runner security & secrets | ~2 h |
| 14 | [Custom Plugins & Testing](14-custom-plugins-testing.md) | Custom module with AnsibleModule (JSON contract, validation, check mode) · filter/lookup plugins · ansible-lint as policy · **Molecule role testing + idempotence step** | ~3 h |
| 15 | [AWX / AAP](15-awx-aap.md) | AWX vs Tower vs AAP · object model · surveys & self-service · workflows with approval gates · execution environments & mesh · RBAC & audit · ops debugging | ~1.5 h |
| 16 | [Scenario Cookbook](16-scenario-cookbook.md) | Six end-to-end projects: LEMP stack · blue-green · fleet patching + reboots · hardening baseline · user lifecycle · **DR failover runbook** · STAR presentation technique | ~5 h |
| 17 | [Interview Cheat Sheet](17-interview-cheatsheet.md) | 55 rapid-fire Q&A · comparison tables · precedence card · junior-vs-SDE-3 language · questions to ask them · 2-week sprint plan | ~1.5 h first pass, 20 min/rep |
| 18 | [Last-Minute Revision](18-last-minute-revision.md) | Everything compressed: ⚡ identity & precedence · numbers table · write-from-memory snippets · 7 scenario blueprints · 15 traps · day-of checklist | 45 min / 30 min / 10 min |

---

## 🚀 Fast routes (pick by how much time you have)

| You have | Route |
|---|---|
| **45 min** | File 18 only |
| **1 day** | File 18 full pass → files 04, 08, 10 (scenario rounds) → sleep |
| **1 week (~2 weeks at 2h/day compressed)** | 00 (steps 1–8) → 01 → 02 → 03 → 04 → 05 → 08 → 10 → 17 |
| **2 weeks** | 00 → 01–11 in order → 16 (projects 1, 2, 6) → 17 → 18 |
| **Full mastery (~4 weeks)** | Everything in order: 00 → 01 … 18, labs included |

## ✅ After each file, you should be able to…

| File | Litmus test |
|---|---|
| 01 | Explain in 30 s how a module travels and executes on a target |
| 02 | Build a 3-env inventory with groups and target `web:!canary` blind |
| 03 | Write the app-release playbook (validate, notify, flush, health-check) from memory |
| 04 | Recite precedence anchors instantly; prove `-e` beats `set_fact` |
| 05 | Explain import vs include and why when+loop is per-item |
| 06 | Generate an nginx upstream block from `groups['web']` in Jinja2 |
| 07 | Scaffold a role and place knobs in defaults vs vars correctly |
| 08 | Design rollback for any deploy in block/rescue terms |
| 09 | Set up per-env vault-ids and never leak a secret in logs |
| 10 | Whiteboard the zero-downtime rollout end-to-end |
| 11 | Name the 5-layer tuning checklist with expected impact |
| 12 | Answer the Terraform-vs-Ansible boundary without hesitation |
| 13 | Say exactly where Ansible fits (and doesn't) in a K8s world |
| 14 | Sketch a custom module skeleton with check-mode support |
| 15 | Design self-service automation with approvals & RBAC |
| 16 | Tell 2–3 project stories with numbers and rejected alternatives |
| 17 | Answer all 55 rapid-fires in < 20 min |
| 18 | Walk in calm. 🚀 |
