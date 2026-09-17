# Terraform in Azure DevOps / CI-CD — Interview Questions

> **Cloud:** Azure · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. Why run Terraform in CI/CD instead of locally?**
**Answer:** For consistency, reviewability, and auditability — the pipeline applies exactly the reviewed plan with the right credentials, locking, and logs.

**A2. What are the standard pipeline stages for Terraform?**
**Answer:** `fmt`/`validate` → `init` → `plan` → (approval) → `apply`, plus optional `destroy` for ephemeral environments.

**A3. How does Azure DevOps run Terraform?**
**Answer:** Via the `TerraformTaskV4` tasks (init/validate/plan/apply) or a plain script task running the Terraform CLI in a pipeline.

**A4. What is a service connection?**
**Answer:** An Azure DevOps connection storing credentials/identity (e.g. an ARM service principal) that pipelines use to authenticate to Azure.

**A5. What is `terraform plan -detailed-exitcode`?**
**Answer:** Exits 0 (no changes), 1 (error), or 2 (changes present) so the pipeline can branch on whether there are diffs.

**A6. What is `terraform fmt -check`?**
**Answer:** Fails the pipeline if files aren't canonically formatted, instead of rewriting them.

**A7. How should the pipeline authenticate to Azure for Terraform?**
**Answer:** Prefer OIDC federation (or a service connection backed by a service principal) with least-privilege roles — avoid long-lived secrets where possible.

**A8. Why store the plan artifact between plan and apply?**
**Answer:** So `apply` executes the exact reviewed plan (`terraform apply <planfile>`), even if the branch changed in between.

**A9. What is the role of the state backend in CI?**
**Answer:** Azure Storage backend gives the pipeline shared, locked state so runs are consistent and serialized.

**A10. What are common tools for Terraform in Azure DevOps?**
**Answer:** The built-in Terraform task, Azure CLI tasks, GitHub Actions (for GH-hosted repos), and Terraform Cloud/Enterprise run tasks.

**A11. What is `tflint`?**
**Answer:** A third-party linter with Azure-specific checks (e.g. valid VM sizes, missing tags) used as an extra gate.

**A12. What does `checkov`/`tfsec` do in CI?**
**Answer:** Static security scanning of Terraform (open NSG rules, unencrypted storage, exposed secrets) to fail the build early.

**A13. What is `terraform apply -auto-approve`?**
**Answer:** Skips interactive confirmation — use only in CI after the plan was reviewed.

**A14. What is the difference between `fmt`, `validate`, and `plan` gates?**
**Answer:** `fmt` checks style, `validate` checks syntax/references, `plan` computes real changes against state/Azure. They run cheapest-first.

**A15. What is an environment/approval gate in Azure Pipelines?**
**Answer:** A deployment environment with required approvers that must approve before the apply stage runs against that environment.

## Case B — Advanced / Senior

**B1. Describe a secure Azure DevOps flow with OIDC.**
**Answer:** Configure a federated credential on the service principal tied to the pipeline's service connection; the pipeline gets short-lived tokens, runs plan with a read-only role and apply with a write role (separate service connections), so planning can't mutate anything.

**B2. What is least privilege for plan vs apply in Azure?**
**Answer:** Use two service connections/principals: plan with Reader + minimal data permissions, apply with the scoped Contributor/custom role, assuming the apply identity only in the apply stage.

**B3. How do you review a large plan in Azure DevOps?**
**Answer:** Publish the plan as a pipeline artifact/comment, require manual approval before apply, use policy-as-code (OPA/Conftest or Azure Policy) to block risky changes, and keep PRs small.

**B4. How do you handle multiple Azure environments in one pipeline?**
**Answer:** Stages per environment (dev → staging → prod) with per-stage variable groups (subscription, state key, tfvars), approval gates between stages, and promotion of the same code.

**B5. What is the "plan vs apply drift" problem and its fix?**
**Answer:** Config changed between planning and applying. Store the binary plan and apply it directly; re-plan if the branch changed.

**B6. How do you implement policy-as-code for Azure with Terraform?**
**Answer:** Tools like OPA/Conftest (Rego policies) or Checkov custom policies scan `terraform plan -json` (or config) in the plan stage and fail on violations (e.g. NSG rule 0.0.0.0/0 on RDP).

**B7. How do you add cost estimation to the pipeline?**
**Answer:** Infracost parses `terraform plan -json` and comments estimated monthly cost deltas on the PR, so cost changes are visible before merge.

**B8. How do you keep the provider lock file consistent in CI?**
**Answer:** Commit `.terraform.lock.hcl` and run `terraform init` (not always `-upgrade`) in CI; bump versions deliberately in a separate PR with `init -upgrade`.

**B9. How do you handle CI concurrency and Azure state locking?**
**Answer:** Blob lease locking serializes applies. Additionally, use pipeline concurrency/exclusive locks per environment so only one run applies at a time.

**B10. What is `terraform apply -parallelism` in CI?**
**Answer:** Limits concurrent resource operations — lower it to avoid Azure API throttling on large applies, at some speed cost.

**B11. How do you test Terraform automatically in Azure DevOps?**
**Answer:** Lint (`tflint`/`fmt`), validate, security scan, plan against sandbox state, and integration-test modules (Terratest) that apply/destroy in a dev subscription.

**B12. How do you use variable groups for environment-specific Azure config?**
**Answer:** Store per-env values (subscription ID, state key, tfvars path, admin secrets in Key Vault-linked variable groups) and reference them per stage so the same pipeline serves all environments.

## Case C — Scenario

**C1. A PR's plan shows an NSG opening RDP to 0.0.0.0/0 and the security gate flags it.**
**Answer:** The policy-as-code gate fails the plan stage with a clear message, blocking merge. The author scopes the rule to a specific IP/ASG or removes it, then re-runs. No manual bypass.

**C2. The apply stage fails intermittently with a state blob lease conflict.**
**Answer:** Another run holds the lease (concurrent pipeline or a crashed job). Add per-environment pipeline locks and recover stuck leases with `force-unlock` after verifying nothing is active.

**C3. You want plan on every PR but apply only on merge to main.**
**Answer:** Configure the pipeline: PR → init + plan + publish plan + gates (read-only connection); merge to main → init + apply the stored plan with the write connection and required approval.

**C4. CI reports "no changes" but you expected a new resource.**
**Answer:** Check the environment/stage (state key), variable groups overriding values, and feature flags (`count = 0`). Re-run plan locally with the same vars to compare.

**C5. You need a full audit trail of every production apply.**
**Answer:** Pipeline run logs (plan + apply output), the merged PR, Azure Storage state versioning, and Azure Activity Log entries together form the audit chain; link the pipeline run to the PR.

**C6. Terraform plans take 20 minutes in Azure DevOps. What do you optimize?**
**Answer:** Split large states into per-component states, avoid broad data sources, run plan-only in parallel across components, cache the provider, and consider module-level pipelines so only changed modules re-plan.
