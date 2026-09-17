# Terraform Workspaces & Environments (AWS) — Interview Questions

> **Cloud:** AWS · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What is a Terraform workspace?**
**Answer:** A named, isolated instance of state for the same configuration. `default` exists by default; `terraform workspace new dev` creates another.

**A2. How do you list and switch workspaces?**
**Answer:** `terraform workspace list`, `select <name>`, `new <name>`, and `delete <name>`. Only one workspace is active at a time.

**A3. What does switching workspaces change?**
**Answer:** The state file (and lock) being used. With remote backends, each workspace maps to a separate state path/key.

**A4. What is `${terraform.workspace}`?**
**Answer:** An interpolation that returns the current workspace name, commonly used to suffix resource names or select environment values.

**A5. What is the main use of workspaces?**
**Answer:** Running the same configuration against different environments (dev/staging/prod) with separate state.

**A6. What's the difference between a workspace and a module?**
**Answer:** A workspace is a separate state for the same code; a module is a reusable block of code. Workspaces isolate data; modules reuse logic.

**A7. What's the difference between a workspace and a separate directory?**
**Answer:** Workspaces share one config and codebase; separate directories have their own config files, backend, and possibly different structure.

**A8. Can you run two workspaces at the same time?**
**Answer:** Not from one shell session, but separate processes/CI jobs can run different workspaces concurrently (each locks its own state).

**A9. How do workspaces behave with the S3 backend?**
**Answer:** The backend automatically uses different state keys per workspace (e.g. `env:/prod/terraform.tfstate`) unless you override the key.

**A10. What is `terraform workspace select default`?**
**Answer:** Switches back to the default workspace. Operations affect only that workspace's state.

**A11. What happens if you `terraform destroy` in a non-default workspace?**
**Answer:** It destroys only that workspace's resources, leaving other workspaces untouched.

**A12. How do you create a dev environment from a prod config?**
**Answer:** Create a `dev` workspace and apply the same config with different `-var-file` (e.g. `dev.tfvars`) values, or use a separate directory.

**A13. What is a common problem with using `${terraform.workspace}` in resource names?**
**Answer:** Renaming/renumbering when the workspace changes can force recreation; be consistent and avoid using it where names must be stable.

**A14. What does `terraform workspace show` do?**
**Answer:** Prints the name of the currently active workspace.

**A15. Can workspaces share a lock?**
**Answer:** No — each workspace's state locks independently, so different workspaces can apply concurrently.

## Case B — Advanced / Senior

**B1. Compare workspaces vs separate directories for environments.**
**Answer:** Workspaces share one codebase (good when environments are near-identical) but make it hard to diverge structurally and risk one bad change hitting prod. Separate directories (or one repo with per-env folders) allow different backends, providers, versions, and structure per environment — generally the safer default for prod.

**B2. How do you handle per-environment values with workspaces?**
**Answer:** Use a map keyed by workspace name (`locals { env = var.configs[terraform.workspace] }`) or pass `-var-file=dev.tfvars` per workspace. Choose one convention and enforce it in CI.

**B3. What are the risks of a single workspace config for prod and dev?**
**Answer:** Shared code means a change applied to dev can be applied to prod with only a `select` — no structural isolation. Mitigate with CI promotion, branch protection, and separate state/backends.

**B4. How do you promote a change across environments with workspaces?**
**Answer:** Plan/apply in dev, verify, then apply the same code (different workspace) to staging, then prod — ideally with the same plan output reviewed and version-pinned modules so behavior is identical.

**B5. How do remote backends name workspace state?**
**Answer:** S3 uses `env:/<workspace>/<key>` by default; some backends use separate containers/folders. You can use `workspace_key_prefix` (Terraform Cloud) or set the key explicitly per environment directory.

**B6. What is `terraform.workspace` best avoided for?**
**Answer:** Secrets selection is fine if structured, but avoid putting it in IAM policy names or anything with strict naming rules. Also avoid heavy conditional resource topologies based on workspace — that reintroduces the "one config" fragility.

**B7. How do you migrate from workspaces to per-environment directories?**
**Answer:** Create the new directory with its own backend, then `terraform state mv -state-out` (or `-state=`) resources from the old workspace's state into the new one, or re-import. Verify with plan before deleting the old workspace.

**B8. Explain the `-state` flag and when you'd use it.**
**Answer:** It runs a command against a specified state file path instead of the active backend — useful for one-off migrations, state surgery, and importing into a state that isn't the current workspace's.

**B9. How do you prevent accidental prod destruction with workspaces?**
**Answer:** Add `prevent_destroy` on critical resources, require manual approval in CI for prod workspace applies, restrict prod credentials, and use `workspace`-aware CI config so destroy is blocked outside dev.

**B10. How does CI typically know which workspace to use?**
**Answer:** From the branch or job parameters — e.g. `main` → prod workspace, PR → dev. The pipeline sets `terraform workspace select` (or `TF_WORKSPACE` env var) before plan/apply.

**B11. What is `TF_WORKSPACE`?**
**Answer:** An environment variable that selects the workspace for a Terraform command, convenient in CI where you can't run interactive `workspace select`.

**B12. What is Terragrunt and how does it relate to this problem?**
**Answer:** A wrapper that keeps Terraform DRY across environments using `terragrunt.hcl`: it manages remote state config, dependencies, and generates backend/provider blocks, so each environment can be a thin directory without duplicating backend code.

## Case C — Scenario

**C1. Dev and prod are drifting apart — you need prod to keep strict isolation.**
**Answer:** Split into per-environment directories with separate backends, providers, and state, so prod has its own code path. Keep shared modules for the common parts, and gate prod behind branch protection and approvals.

**C2. A dev accidentally ran `terraform destroy` in the prod workspace.**
**Answer:** Immediately assess via the state/version history what was removed, restore from S3 state version if needed, and re-apply config to rebuild. Then add guardrails: `prevent_destroy`, separate credentials, CI-only prod applies with approval.

**C3. You have 12 environments that are nearly identical. Workspaces or directories?**
**Answer:** Workspaces with per-environment tfvars and CI-driven selection scale well here, since the structure is identical. If a few environments need custom resources, use enable flags or a hybrid (directories for exceptions).

**C4. A team wants to run experiments without touching the shared dev environment.**
**Answer:** Give each developer an isolated workspace (or personal backend key) and their own tfvars; optionally ephemeral sandbox accounts. Ensure naming uses workspace suffix so resources don't collide.

**C5. You're adopting Terraform Cloud. How do you map existing workspaces?**
**Answer:** Create a TFC workspace per environment, configure it with the same VCS repo and variables, migrate state with `terraform state push` (after pull/backup), and set `workspace_key_prefix` or per-workspace variable sets accordingly.

**C6. Management wants a single command to deploy to all environments in order.**
**Answer:** Build a CI/CD pipeline (or Terragrunt `run-all`) that iterates dev → staging → prod, gating each stage on the previous success and on approvals for prod. Avoid one monolithic apply spanning environments.
