# 15 — AWX / Ansible Automation Platform (🟢 4 · 🟡 5 · 🔴 5)

> Course ref: [15-awx-aap.md](../ansible-mastery/15-awx-aap.md)

## 🟢 Basic

**Q1. AWX vs Tower vs AAP?**
> A: AWX = open-source upstream (free, community). Tower = Red Hat's old commercial version (legacy name). AAP 2.x = current platform: controller + automation hub + execution environments + automation mesh.

**Q2. What is a Job Template?**
> A: The reusable launch unit: playbook (from a project) + inventory + credentials + params — optionally with a survey — that users/CI launch with RBAC. The bridge between "YAML in git" and "button someone can press."

**Q3. What are credentials in AAP?**
> A: Encrypted-at-rest entries (machine SSH, vault passwords, cloud keys, custom types) injected into the execution environment only at job runtime — never rendered in UI/logs, never stored in playbooks.

**Q4. What is an Execution Environment?**
> A: Container image with ansible-core + collections + Python/system deps — the reproducible, versioned runner. Built with `ansible-builder`, run by controller/`ansible-navigator`.

## 🟡 Intermediate

**Q5. What are surveys and why do they matter?**
> A: Guided forms on job templates (text/choice/boolean → extra_vars) — self-service for non-Ansible users with validated inputs. They turn playbooks into internal products.

**Q6. Explain Workflow Templates and the approval node.**
> A: DAGs of job templates + approval + failure paths: lint → staging → **approval** → prod → notify. The approval node makes prod deploys human-gated with every click audited — governance as a feature.

**Q7. What is automation mesh?**
> A: Scale-out execution nodes placed near hosts (regions/VPCs) connected back to the control plane — solves control-node network/scale limits for 10k+ hosts or segmented networks.

**Q8. Where does the automation code live in an AAP world?**
> A: Still in git — AAP projects sync from SCM. The platform is the *executor/auditor*, never the source of truth; UI-editing playbooks is an anti-pattern.

**Q9. Job queued forever — diagnose.**
> A: Check instance group capacity (worker slots full), EE image pull failures on the node, inventory plugin hangs (cloud API timeouts) before task start, or a dependency job holding resources — API `/api/v2/jobs/{id}/` shows status and execution node first.

## 🔴 Advanced

**Q10. Design automation for 40 devs, 3 envs, mandatory prod approval.**
> A: Org + teams; project(s) from git; inventories per env; job templates with surveys per operation; workflow: lint → staging → approval → prod; devs `execute` on staging templates only; approvers group for prod; notifications per template; CI integrates via API tokens (RBAC-scoped) — nobody has SSH; every run attributed and logged.

**Q11. How does AAP change the secrets model vs plain Ansible?**
> A: Central encrypted credential store with per-object RBAC, runtime injection into EEs, no files on runners, full audit of usage; custom credential types extend it to anything. Vault passwords, SSH keys, and cloud creds stop being ops-cargo and become governed assets.

**Q12. What is job slicing and when does it apply?**
> A: Splits a single job's inventory across multiple execution nodes running in parallel — for huge inventories (10k+) where one job would serialize. Applies to fleet-wide operations where per-slice independence is acceptable; breaks cross-host ordering guarantees, so not for orchestration-critical runs.

**Q13. Compare AWX (self-hosted free) vs licensed AAP for an enterprise.**
> A: AWX: community support, faster-moving, you own upgrades/SLAs. AAP: certified EEs, support, hub with curated/content signing, mesh at scale, analytics. Decision drivers: compliance/support requirements, scale, and whether the org treats automation as production-critical infrastructure.

**Q14. What operational pitfalls do teams hit with AAP?**
> A: EE drift (collections bumped in git but EEs not rebuilt → "module not found" on one node), RBAC rot (org admins everywhere), surveys growing business logic (giant Jinja conditionals in one playbook), no notifications on failure, and treating the controller DB as the inventory source of truth.
