# Terraform in CI/CD (AWS) — Interview Questions

> **Cloud:** AWS · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. Why run Terraform in CI/CD instead of laptops?**
**Answer:** For consistency, reviewability, and auditability — a pipeline applies exactly the reviewed plan, with the right credentials, logging, and locking, every time.

**A2. What are the standard pipeline stages for Terraform?**
**Answer:** `fmt`/`validate` (lint) → `init` → `plan` → (review/approval) → `apply`, plus optional `destroy` for ephemeral environments.

**A3. What is `terraform plan -detailed-exitcode`?**
**Answer:** It exits 0 (no changes), 1 (error), or 2 (changes present), so CI can branch on whether a plan has diffs.

**A4. What is `terraform fmt -check`?**
**Answer:** It fails the pipeline if files aren't canonically formatted, instead of rewriting them.

**A5. How does CI authenticate to AWS for Terraform?**
**Answer:** Ideally via OIDC federation (short-lived tokens) to assume an IAM role, or via instance roles on self-hosted runners. Avoid long-lived access keys.

**A6. What is `-input=false`?**
**Answer:** It disables interactive prompts so a missing variable fails the run instead of hanging the pipeline.

**A7. Why store the plan artifact between stages?**
**Answer:** So `apply` executes the exact reviewed plan (with `terraform apply <planfile>`), even if the branch changed in between.

**A8. What is the role of the state backend in CI?**
**Answer:** It gives the pipeline shared state with locking (S3 + DynamoDB), so runs are consistent and serialized.

**A9. What are common CI tools for Terraform?**
**Answer:** GitHub Actions, GitLab CI, Jenkins, AWS CodePipeline/CodeBuild, and dedicated tools like Atlantis or Terraform Cloud run tasks.

**A10. What is a "plan comment" on a pull request?**
**Answer:** The pipeline posts the plan output as a PR comment so reviewers can see infrastructure changes before merge — Atlantis and Terraform Cloud do this natively.

**A11. What is `terraform validate`?**
**Answer:** A static check of syntax and references, run early and cheaply in CI before any credentials or state are needed.

**A12. What is `tflint`?**
**Answer:** A third-party linter with AWS-specific rules (e.g. instance type validity, missing tags) used as an extra quality gate.

**A13. What does `checkov` or `tfsec` do in CI?**
**Answer:** Static security scanning of Terraform (misconfigurations like open SGs, unencrypted buckets) to fail the build early.

**A14. What is `terraform apply -auto-approve`?**
**Answer:** Skips the interactive confirmation. Use only in CI after the plan was reviewed; never for destructive ad-hoc runs.

**A15. What's the difference between `fmt`, `validate`, and `plan` in CI?**
**Answer:** `fmt` checks style, `validate` checks syntax/references, and `plan` computes real changes against state and AWS. They run in that order, cheapest first.

## Case B — Advanced / Senior

**B1. Describe a secure CI flow with OIDC.**
**Answer:** The pipeline authenticates to AWS via OIDC (GitHub Actions → IAM role with a trust policy restricted to the repo/branch), receives short-lived creds, then runs plan (read/plan-only role) and apply (wider role) separately, so plan can't mutate anything.

**B2. What is the principle of least privilege for plan vs apply in CI?**
**Answer:** Use two roles: a plan role with read-only permissions and a separate apply role with write permissions, assuming the apply role only at the apply stage. This limits the blast radius of a compromised PR.

**B3. How do you review a large plan in CI?**
**Answer:** Post a trimmed, formatted plan (or a link to it), require approvals before apply, use policy-as-code (OPA/Conftest/Sentinel) to auto-block risky changes, and keep changes small per PR.

**B4. What is Atlantis and how does it differ from generic CI?**
**Answer:** Atlantis runs Terraform from PR comments/events (`atlantis plan`, `atlantis apply`) with automatic plan output on PRs and locking. It specializes in Terraform review workflows versus hand-rolled pipeline stages.

**B5. How do you handle multiple environments in one CI pipeline?**
**Answer:** Map branches to environments (main → prod) or use matrix jobs per env with per-env backend/var files, promote plans across envs with approvals between stages, and share modules via the repo.

**B6. What is a "plan vs apply drift" problem and how do you solve it?**
**Answer:** Config changed between planning and applying, so the applied plan no longer matches main. Store the binary plan and apply it directly, and gate merges on up-to-date plans.

**B7. What is policy-as-code and which tools implement it?**
**Answer:** Automated rules that reject plans violating policy (e.g. S3 without encryption). Implemented via OPA/Conftest, HashiCorp Sentinel, or Open Policy Agent integrated at the plan step.

**B8. How do you add cost estimation to the pipeline?**
**Answer:** Tools like Infracost parse `terraform plan -json` and comment estimated monthly cost diffs on the PR, so cost changes are visible before merge.

**B9. How do you keep the lock file consistent in CI?**
**Answer:** Commit `.terraform.lock.hcl` to the repo and run `terraform init` (not always `-upgrade`) in CI so provider versions match local dev. Run `init -upgrade` deliberately in a separate PR when bumping versions.

**B10. How do you handle CI concurrency and state locking?**
**Answer:** DynamoDB locking serializes applies across jobs. Additionally, CI should cancel/queue overlapping runs for the same environment to avoid queued stale plans.

**B11. What is `terraform apply -parallelism` in CI?**
**Answer:** It limits concurrent resource operations. Lowering it can reduce API throttling on large applies, at the cost of speed.

**B12. How do you test Terraform code automatically?**
**Answer:** Lint (`tflint`, `fmt`), validate, security scan (`tfsec`/`checkov`), plan against sandbox state, and integration-test modules with Terratest (real apply/destroy in a dev account).

## Case C — Scenario

**C1. A PR's plan shows an S3 bucket policy change that a security rule flags. How does CI respond?**
**Answer:** The policy-as-code gate fails the pipeline with a clear message before apply, blocking merge. The author fixes the policy or gets an explicit exception, then re-runs. No manual "I'll fix it later."

**C2. Your GitHub Actions apply job fails intermittently with a state lock error.**
**Answer:** Something else holds the DynamoDB lock (a concurrent run or a crashed job). Ensure only one apply per environment runs (concurrency groups in Actions), and recover stuck locks with `force-unlock` after verifying nothing is active.

**C3. You want plan to run on every PR but apply only on merge to main.**
**Answer:** Configure the pipeline: PR → `init` + `plan -detailed-exitcode` + post plan + security gates (read-only role); push to main → `init` + `apply <saved plan>` with the write role and required approval. Store the plan artifact between jobs.

**C4. A dev pushes a change and CI reports "no changes" but you expected a resource.**
**Answer:** Check that the change is in the right workspace/environment (backend key), that variables aren't overriding it, and that the resource isn't `count = 0`/feature-flagged off. Re-run `plan` locally with the same vars to compare.

**C5. You need an audit trail of every production apply.**
**Answer:** CI logs (with plan + apply output), VCS history of the merged PR, S3 state versioning, and CloudTrail API events together form the audit chain. Export plan artifacts and link the PR to the pipeline run.

**C6. Terraform in CI is slow — plans take 20 minutes. What do you optimize?**
**Answer:** Narrow state per component, use `-target` sparingly (not as routine), reduce data source scans, tune provider caching, run plan-only in parallel across components, and consider module-level pipelines so only changed modules re-plan.
