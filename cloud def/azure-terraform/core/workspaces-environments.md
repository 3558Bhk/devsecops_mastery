# Terraform Workspaces & Environments (Azure) — Interview Questions

> **Cloud:** Azure · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~5 min

---

## Case A — Basic

**A1. What is a Terraform workspace?**
**Answer:** A named, isolated instance of state for the same configuration. `default` exists initially; `terraform workspace new dev` creates another.

**A2. What changes when you switch workspaces?**
**Answer:** The state file (and lock) in use. With the Azure backend, each workspace maps to a separate state blob/key.

**A3. How do you manage workspaces?**
**Answer:** `terraform workspace list/new/select/delete/show`. Only one is active at a time.

**A4. What is `${terraform.workspace}`?**
**Answer:** An interpolation returning the current workspace name, often used to suffix resource names or select per-environment values.

**A5. What is the main use of workspaces?**
**Answer:** Running one configuration against different environments (dev/staging/prod) with isolated state.

**A6. How do workspaces behave with the Azure (azurerm) backend?**
**Answer:** The backend stores each workspace's state under a different key/prefix by default, keeping them isolated in the same storage container.

**A7. What's the difference between a workspace and a module?**
**Answer:** A workspace isolates state for the same code; a module reuses code. They solve different problems.

**A8. What's the difference between a workspace and a separate directory?**
**Answer:** Workspaces share one codebase; separate directories have their own config, backend, and possibly structure — better when environments diverge.

**A9. Can two workspaces apply concurrently?**
**Answer:** Yes — from separate processes/CI jobs, since each workspace's state locks independently.

**A10. What does `terraform destroy` do in a non-default workspace?**
**Answer:** Destroys only that workspace's resources; other environments are unaffected.

**A11. How do you create a dev environment from prod config?**
**Answer:** Create a `dev` workspace and apply the same config with different `-var-file` (e.g. `dev.tfvars`) values.

**A12. What is `terraform workspace select default`?**
**Answer:** Switches back to the default workspace.

**A13. What is `TF_WORKSPACE`?**
**Answer:** An environment variable selecting the workspace for a command — handy in CI without interactive prompts.

**A14. Why be careful using `${terraform.workspace}` in resource names?**
**Answer:** Names may be immutable in Azure and changing workspace can force recreation; keep naming stable.

**A15. How do you set different subscriptions per workspace?**
**Answer:** Workspaces alone don't change credentials — combine with provider aliases or per-environment tfvars holding `subscription_id`, or use separate directories.

## Case B — Advanced / Senior

**B1. Compare workspaces vs separate directories for Azure environments.**
**Answer:** Workspaces suit near-identical environments sharing one codebase; directories suit structurally different environments with separate backends, providers, and versions. For production isolation, separate directories (or per-env backends) are the safer default.

**B2. How do you handle per-environment values with workspaces?**
**Answer:** Either a map keyed by workspace name (`var.configs[terraform.workspace]`) or per-workspace `-var-file` in CI. Pick one convention and enforce it in the pipeline.

**B3. What are the risks of one workspace config for dev and prod?**
**Answer:** Shared code means a change applied to dev can hit prod with a single `select` — no structural isolation. Mitigate with CI promotion, approvals, and separate state/backends.

**B4. How do you promote a change across Azure environments?**
**Answer:** Plan/apply in dev, verify, then apply the same pinned code to staging and prod with approvals between stages, ensuring provider/module versions are identical.

**B5. How does the Azure backend store workspace state, and how do you control the key?**
**Answer:** By default it prefixes workspace names into the blob path; you can set `key` explicitly per environment directory (with `workspace_key_prefix` in some backends) for full control.

**B6. How do you migrate from workspaces to per-environment directories?**
**Answer:** Create the new directory with its own backend, move resources with `terraform state mv -state-out` (or import), verify plans are clean, then retire the old workspace.

**B7. How do you prevent accidental prod destruction?**
**Answer:** `prevent_destroy` on critical resources, CI approval gates for prod, restricted prod credentials, and separate state/backends so a dev mistake can't reach prod.

**B8. How does CI know which workspace/environment to use?**
**Answer:** From the branch or job parameter — e.g. `main` → prod. The pipeline sets `TF_WORKSPACE` (or selects the environment directory) before plan/apply.

**B9. What is Terragrunt and how does it help Azure multi-environment setups?**
**Answer:** A wrapper keeping Terraform DRY across environments: `terragrunt.hcl` files manage backend config (storage account/container/key), provider blocks, and dependencies per environment directory.

**B10. How do you share one Azure subscription across environments with isolation?**
**Answer:** Use separate resource groups per environment (named with the env), separate state keys, and RBAC scoping so dev identities can't touch prod resource groups.

**B11. What is the `-state` flag's role in environment migrations?**
**Answer:** It runs a command against a specified state path instead of the active backend — useful for one-off moves between environment states.

**B12. How do you audit which environment a resource belongs to?**
**Answer:** Enforce tags (e.g. `environment = terraform.workspace`) on every resource, and name resources with env prefixes, so billing/operations can always attribute resources.

## Case C — Scenario

**C1. Dev and prod are drifting apart; you need strict prod isolation.**
**Answer:** Split into per-environment directories with separate backends/providers/state, keep shared modules for common parts, and gate prod behind approvals and restricted credentials.

**C2. A dev accidentally ran `terraform destroy` in the prod workspace.**
**Answer:** Assess damage from state/activity logs, restore resources by re-applying config (or from backups), then add guardrails: `prevent_destroy`, separate credentials, CI-only prod applies.

**C3. You have 12 near-identical Azure environments. Workspaces or directories?**
**Answer:** Workspaces with per-environment tfvars and CI-driven selection scale well. Use enable flags for minor differences, and directories only for the exceptions.

**C4. A team wants to experiment without touching the shared dev environment.**
**Answer:** Give each developer an isolated workspace (or personal backend key/resource group) with their own tfvars, so experiments don't collide with shared state.

**C5. You're adopting Terraform Cloud for your Azure estate. How do you map workspaces?**
**Answer:** Create a TFC workspace per environment with the same VCS repo and variables, migrate state via `terraform state pull/push`, and use variable sets for shared Azure credentials.

**C6. Management wants one command to deploy to all Azure environments in order.**
**Answer:** A CI/CD pipeline (or Terragrunt `run-all`) iterating dev → staging → prod with approvals and per-stage gates — never one apply spanning all environments.
