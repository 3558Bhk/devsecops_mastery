# Case 2 — General Questions (bullet Q&A)

> Level: **general** (working knowledge — the questions mid-level interviews actually ask)
> Format: question → spaced answer → next question

---

### Q1. Why do teams move state from a local file to S3/Azure Storage, and what does the lock table add?

- **Remote state** solves three problems at once:
  - **Shared** — every developer and every CI run reads the same truth.
  - **Safe** — encrypted at rest, versioned (S3 versioning), not on a laptop that can die.
  - **Lockable** — the DynamoDB table (AWS) stores a lease: "whoever last applied holds this lock for N minutes".

- **Lock table detail**:
  - On `apply`, Terraform writes a lock row; on completion it deletes it.
  - If a second `apply` starts while the first holds the lock → it **waits or fails** instead of corrupting state.
  - If the first apply **crashed mid-write**, the lock can go stale → you delete it manually (`aws dynamodb delete-item`) only after confirming no apply is running.

---

### Q2. Two colleagues are applying at the same time and one is blocked on a lock. Walk me through what happens and how you'd resolve it.

- The second apply prints: `Acquiring state lock... timed out` (or waits, if `-lock-timeout` is set).

- Resolution flow:
  1. **Check if an apply is actually running** — ask the first person / check CI logs.
  2. If yes → wait for it to finish; the lock releases automatically.
  3. If no (someone's laptop died) → verify no process holds it, then force-release:
     - AWS: `aws dynamodb get-item --table tf-locks --key ...` to see `ID` and `Path`, confirm, then `delete-item`.
     - Azure: delete the lease blob in the state container.
  4. **Prevention**: CI pipelines apply serially per state; devs use `terraform plan` (which also locks, briefly) not `apply` on shared environments; long applies happen in CI with timeouts + alerts.

---

### Q3. A resource was deleted by hand in the portal (someone "fixed" a bucket directly). What does your next `plan` show, and what do you do?

- `plan` shows: Terraform **doesn't know it's gone** (state still lists it) — it will show **no changes**, or a refresh will show it missing.

- The right sequence:
  1. `terraform plan` first — if it says "No changes", that's already a red flag.
  2. `terraform refresh` (implicit in modern TF) or `terraform plan -refresh-only` → it reads the real world and reports `Error: ... not found` or marks the resource gone.
  3. Decide:
     - **It should exist** → `apply` recreates it (usually what you want).
     - **It was intentionally removed** → `terraform state rm <address>` to forget it, so future plans don't recreate the "deleted" resource.

- The underlying lesson: **out-of-band changes are the #1 source of drift** — the code is the only source of truth; portal edits must be converted back into code.

---

### Q4. When would you use `terraform import`, and show me the flow?

- **When**: a resource exists in the cloud but wasn't created by Terraform (legacy infra, a teammate's one-off, a company-mandated account) — you want Terraform to **adopt** it so it's protected and managed.

- Flow:
  1. Write the resource block **without relying on values** — just the address (e.g. `resource "aws_s3_bucket" "legacy" {}`).
  2. `terraform import aws_s3_bucket.legacy my-existing-bucket-name` (the cloud ID/name).
  3. Terraform reads the real attributes into state; fill the block with those attributes.
  4. `terraform plan` → must be clean (if not, your block doesn't match reality — fix the attributes).
  5. Commit. From now on Terraform manages it.

- Pitfall: if the block's attributes conflict with reality, the next plan will try to "fix" the resource — that's expected but scary; match attributes to the imported values first.

---

### Q5. What are `terraform state mv` and `state rm`, and when do you need them?

- **`state mv`** — moves a resource from one address to another **without touching the cloud** (rename in code / reorganize modules).
  - Example: you refactored `modules/network` → `modules/vpc`; the resource address changed; without `mv` Terraform would destroy + recreate.
- **`state rm`** — forgets a resource in state (used after `import` experiments, or when you deliberately hand a resource back to manual management).
  - ⚠️ `state rm` does **not** delete the cloud resource — it just stops managing it (orphan risk).
- **`state show`** — inspect what's in state for one address.

- Rule: state surgery commands are **last-resort, carefully-logged operations** — do them against a backed-up remote state.

---

### Q6. How do you structure Terraform for multiple environments (dev / staging / prod)?

- **Separate state per environment** — never one state file for all envs (one `apply` should never be able to touch prod).

- Common layouts:
  - **One repo, one folder per env**: `envs/dev/`, `envs/staging/`, `envs/prod/`, each with its own backend key (`dev/terraform.tfstate`).
  - **One root, many workspaces** — `terraform workspace` per env (works, but workspaces share the same config and are harder to reason about — most teams prefer folders).
  - **Terragrunt** — one base config, per-env folders with `generate_blocks` and a source pointer; DRY across 50 envs.

- The values that differ per env come from per-env `terraform.tfvars` (or env vars in CI): name prefixes, sizes, regions.

- Prod gate: approvals (CI environment protection / manual approval step) + never direct-apply from a laptop.

---

### Q7. Secrets are showing up in your state file. What are your options, in order of preference?

- First, understand: state contains what you **pass through variables** — a `db_password` variable's value ends up in state (even with `sensitive = true`, which only hides *display*, not storage).

- Options:
  1. **Don't push secrets through Terraform at all** — have the app read them from a secrets store (AWS Secrets Manager / SSM, Azure Key Vault) at runtime. Terraform creates the store, not the value. *(Best.)*
  2. If the secret must live in infra (e.g. an RDS master password — unavoidable):
     - Remote backend with **encryption** (`encrypt = true` / SAS-backed Azure backend).
     - Restrict state access (bucket policy → only the team/CI role).
     - Rotate the secret periodically.
     - Enable state **versioning** so an accidental commit to Git isn't the only copy lying around.
  3. If a secret was committed to Git: **rotate it immediately**, then clean history (filter-repo) — but rotation is the real fix; history rewriting is cosmetic.

- Also: `sensitive = true` on variables/outputs is table manners — it stops secrets printing in CI logs.

---

### Q8. What happens when you upgrade a provider version? What can go wrong?

- Provider versions are where **schema changes** happen: renamed arguments, new required blocks, changed defaults, new resource behavior.

- What can go wrong:
  - **`validate` errors** — a required argument appeared (fix: add it; usually safe).
  - **`plan` churn** — provider now reads a field differently → spurious diffs (fix: pin the version, or update the code to the new shape).
  - **Behavior change** — e.g. a flag's default flipped; your `apply` would "fix" the world differently (fix: set the attribute explicitly).
  - **Breaking major versions** — e.g. azurerm 4→5, aws 5→6: expect a migration pass.

- Safe upgrade flow:
  1. Bump the version constraint in `required_providers` (or `terraform init -upgrade`).
  2. `terraform validate` → `terraform plan`.
  3. Read every diff; anything unexpected → bisect (upgrade in smaller steps).
  4. Apply in **dev first**, watch the resources, then staging, then prod.

---

### Q9. Explain the difference between `depends_on` and natural dependencies. When is `depends_on` actually correct?

- **Natural dependency** — you reference a resource's attribute (`vpc_id = aws_vpc.main.id`) → Terraform builds the dependency automatically and orders operations (create VPC before subnets).
- **`depends_on`** — explicit ordering when there's **no attribute reference** but a logical ordering exists.

- Correct uses of `depends_on`:
  - Ordering `null_resource` / `local-exec` steps.
  - Ensuring a module's resources exist before a data source that reads them (`data "..." { depends_on = [module.x] }`) — data sources otherwise don't track the module.
  - A `terraform_remote_state` read that needs the other stack applied.

- Wrong use: slapping `depends_on` to fix a plan diff you don't understand — that hides the real problem.

---

### Q10. What is `terraform taint`, and when do you reach for it?

- `taint` marks a resource **for replacement at the next apply** (destroy + recreate), even though nothing in the code changed.

- When it's right:
  - A resource is **misbehaving** but healthy-looking (a corrupted volume, a buggy Lambda zip that `plan` thinks is unchanged because code hash didn't move).
  - You want to **re-run** a one-shot thing (a `null_resource` migration script) after a failed partial run.

- When it's dangerous:
  - Tainting a **stateful** resource (RDS, volume) = data loss unless you've taken a snapshot/backup first.
  - Modern alternative for code: `create_before_destroy` lifecycle, or just change an attribute to force the recreation deliberately.

- Command: `terraform taint aws_instance.web` → next `apply` shows `-/+` for it.

---

### Q11. Walk me through a CI/CD pipeline for Terraform (the standard shape).

- **On pull request** (the "plan" gate):
  1. Checkout code at the PR branch.
  2. `terraform init -backend=false` (no state access needed).
  3. `terraform validate` + `terraform fmt -check` (style) — fail fast.
  4. `terraform init` (with backend) + `terraform plan` → **upload the plan as an artifact / comment on the PR**.
  5. Humans review the actual diff. CI **never applies** from a branch.

- **On merge to main** (the "apply" step):
  1. Re-run `plan` in the same job (so what's applied == what was planned — store the plan file and `apply saved.plan`).
  2. **Approval gate for prod** (manual approval / protected environment).
  3. `terraform apply -auto-approve plan-file`.
  4. `terraform output` → pass outputs (URLs) to downstream smoke tests.

- **Credentials**: injected as **secret variables** from the CI's vault (never in the repo); short-lived / scoped (CI role can `apply` in dev, only *plan* in prod).

- **Drift check**: a scheduled nightly `plan` that alerts if the real world diverged from code.

---

### Q12. A module you depend on gets a breaking change. How do you handle it?

- First: **pin your module versions** (`source` + `version = "1.2.0"` or a Git tag) — you're never ambushed; upgrades are deliberate.

- Handling flow:
  1. Read the module's changelog / diff between versions.
  2. Upgrade in a **branch**, run `plan` against dev.
  3. Classify the change:
     - Input renamed → update your `module {}` call.
     - A resource's type/shape changed inside the module → this can force **replace** — check the plan line by line; you may need a `state mv` or a migration plan.
     - New required input → supply it (default in your vars file).
  4. Apply in dev, verify, promote.
  5. If the breakage is too risky → **fork the module** into your repo (vendor it) and control it yourself.

- The principle: **modules are dependencies** — same discipline as upgrading a library (pin, test, staged rollout).
