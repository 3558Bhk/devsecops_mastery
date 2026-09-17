# 8. Best Practices, Gotchas & Security

> **⏱️ Time to complete: ~35 min** (read + audit your own code against the checklist)

## 8.1 Repository Structure (the pattern that scales)

```
infra/
├── .terraform.lock.hcl            # commit
├── modules/                       # reusable, versioned library
│   ├── vpc/
│   ├── compute/
│   └── database/
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── backend.tf             # s3 key = "dev/global"
│   │   ├── terraform.tfvars       # non-secret values (commit)
│   │   └── secrets.auto.tfvars    # (git-ignored; or use SSM/Key Vault)
│   ├── staging/
│   └── prod/
├── pipelines/                     # CI/CD (see cross-cloud/02)
└── README.md
```

**One state per environment (or per service+environment).** Never one giant global state for a whole company.

## 8.2 The Non-Negotiables (checklist)

- [ ] **Remote backend with locking** for anything shared/production.
- [ ] **Pin provider versions** (`~> 5.0`) and **commit `.terraform.lock.hcl`**.
- [ ] **`terraform fmt -check`** and **`terraform validate`** in CI + pre-commit.
- [ ] **No secrets in code, no secrets in `tfvars`, no secrets in state** (use data sources / secret managers).
- [ ] **`plan` before `apply`** — in CI, plan is a PR gate with a human review.
- [ ] **`prevent_destroy`** on data-bearing resources (DB, KMS keys, S3 buckets with data).
- [ ] **`force_destroy`/`skip_final_snapshot` = false in prod** (env-gated).
- [ ] **Tags everywhere** via `default_tags` (AWS) / `tags` local (Azure).
- [ ] **Smallest possible scopes** for IAM/RBAC (least privilege for the Terraform role).
- [ ] **`terraform test` / policy checks** (Checkov, tfsec, Sentinel) in CI.

## 8.3 Naming Conventions

```hcl
locals {                          # named expressions
  name_prefix = "${var.project}-${var.environment}"   # e.g. "acme-prod"
  # resources: aws_instance.web, aws_vpc.main
  # names:     "${local.name_prefix}-web", "${local.name_prefix}-vpc"
}
```

- Keep **resource *addresses*** (left of `.`) short and semantic: `aws_instance.web`, not `aws_instance.1`.
- Keep **cloud *names*** (the `name =` arg) consistent and prefixed: `${prefix}-web`.
- Never embed a `count` index in the cloud name (`web-${count.index}`) — it's fragile across replacements.

## 8.4 Secrets Management (the #1 real-world pain)

**Never do this:**
```hcl
variable "db_password" { default = "P@ssw0rd" }   # NO — never hardcode secrets
```

**Do this:**
```hcl
# 1) Generate + store in a secrets manager, then read it
resource "aws_secretsmanager_secret" "db" {   # create a secret in Secrets Manager
  name = "${local.name_prefix}/db"            # the secret name
}

# ... or, for consumption:
data "aws_secretsmanager_secret_version" "db" {   # read an existing secret
  secret_id = var.db_secret_arn               # the secret's ARN
}
# use: password = jsondecode(data.aws_secretsmanager_secret_version.db.secret_string).password

# Azure: Key Vault
data "azurerm_key_vault_secret" "db" {         # read a Key Vault secret
  name         = "db-password"                 # the secret name
  key_vault_id = var.key_vault_id              # the Key Vault's id
}
# use: password = data.azurerm_key_vault_secret.db.value
```

- If you *must* pass a secret as a variable, mark it `sensitive = true`, supply it via `TF_VAR_*` or a **git-ignored** `*.auto.tfvars`, and **rotate** it (state history keeps old values).
- Better: **generate with `random_password`** + store in the secret manager (never output it).

## 8.5 Least Privilege for the Terraform Itself

The IAM/RBAC role that runs Terraform should get **only** the actions it needs. Practical approach:
1. Run `terraform plan` with a permissive role and collect **`UnauthorizedOperation`/`AuthorizationFailed`** errors.
2. Grant exactly those, scoped to resource ARN/ID where possible.
3. Re-run until clean.

For AWS, the classic permissive starting point (tighten after):
```json
{ "Effect": "Allow", "Action": ["ec2:*","s3:*","iam:PassRole","rds:*"], "Resource": "*" }
```
For Azure, start with **Contributor** on a scoped RG, then narrow to per-service roles.

## 8.6 Idempotency & Drift Hygiene

- Second `plan` after a clean `apply` **must** be empty. If it's not, you have a non-idempotent resource (often: `random` in a name, `uuid()` in an arg, a `remote-exec` that changed something, or a cloud default you didn't set).
- Schedule a **`plan -refresh-only`** (or a `plan` in CI) to catch drift early.
- Prefer **`ignore_changes`** for attributes you genuinely don't own; don't use it to hide a broken model.

## 8.7 The `-target` Flag (know why you should avoid it)

`-target` limits a plan/apply to specific resources. **It breaks the guarantee of whole-graph consistency** — it can leave dependencies dangling, and the plan may be misleading.
- ✅ Legitimate: quick local debugging, targeted import verification.
- ❌ Never: production changes, CI.
- Use `-replace` for targeted *recreation*, and **full plans** for real changes.

## 8.8 Performance & Scale

- `-parallelism=N` — lower (e.g. 5) if you hit API **throttling** (`ThrottlingException`, `429`).
- Split **large states** by service → smaller, faster plans, parallel teams.
- Avoid `data` sources that trigger expensive calls on **every plan** (cache via state, or reference outputs).
- Use `for_each` (not `count`) so you don't accidentally **re-key** resources.
- **Provider `max_retries`** and `assume_role.duration` tuning helps flaky networks.

## 8.9 Testing & Policy

| Layer | Tool | Purpose |
|---|---|---|
| Syntax/format | `terraform fmt`, `terraform validate` | No errors |
| Unit | `terraform test` | Behavior assertions |
| Policy (IaC) | **Checkov**, **tfsec**, **Prisma**, **Sentinel** | Security/compliance (no public S3, encryption on, etc.) |
| Policy (runtime) | OPA/Conftest on plan JSON | Fine-grained gates |
| Cost | **Infracost**, TFC cost estimation | Budget guardrails |
| Integration | Plan against a scratch env | End-to-end |

## 8.10 The Top 15 "Gotchas" (memorize for interviews)

1. **`count` + deleting a middle item** → key shift → unexpected replacement. Use `for_each` with stable keys.
2. **`uuid()` / `random` in an attribute** → new value every plan → perpetual diff. Freeze in a `local`/state.
3. **`for_each` over a `set`** → unordered keys. Use list/map.
4. **Provisioners don't re-run on update** → stale remote state. Model it declaratively.
5. **`-target`** in prod → inconsistent graph. Don't.
6. **State in Git** → secrets in history, merge conflicts, no locking. Use a remote backend.
7. **`force_destroy`** in prod → data loss. Gate by environment.
8. **Ignoring a provider version bump** → breaking changes (e.g. aws 4→5). Pin + review.
9. **Two roots sharing a state** without locking → corruption. Lock it.
10. **Data source value used in `for_each`** → "value is known after apply" error. It must be known at plan.
11. **Refactoring a resource's address** → destroy+create. Use `moved` blocks.
12. **`import` then `destroy`** → deletes a resource you didn't own. Be deliberate.
13. **S3 bucket name is global** → can't have the same name in two regions/accounts. Use unique names (uuidv5).
14. **`depends_on` overuse** → hides a missing reference; prefer explicit attribute references.
15. **`terraform init -reconfigure`** carelessly → can drop/lose state. Back up before backend changes.

## 8.11 Debugging Playbook

| Symptom | First moves |
|---|---|
| Plan shows a change you didn't expect | `terraform show -json plan` → read the `change.actions`; check for non-idempotency or drift. |
| "Provider produced inconsistent result after apply" | Re-plan; check the cloud console for the actual state; often a race. |
| Resource stuck in "creating" | Cloud-side timeout; check console; `state rm` + re-apply if it actually created. |
| Lock error | Wait, or verify the holder is dead → `force-unlock`. |
| Auth error mid-apply | Credentials/role expired (assume-role duration); extend `duration`, re-auth. |
| Huge plan on every run | Find the non-idempotent attribute; add `ignore_changes` or fix the source. |
| `terraform console` hangs | A data source is slow; `TF_LOG=DEBUG` to see which API call. |

## 8.12 The "Senior Engineer" Mental Model

- Terraform is a **declarative reconciler**: config = desired, state+live = current, plan = the diff. Everything (gotchas, features, errors) is a consequence of that.
- **State is the single source of truth for *identity*, not for *truth* about the cloud** (refresh corrects it).
- **The dependency graph is the engine** — create/destroy order, parallelism, and `-target`'s danger all come from it.
- **Modules are your API surface**; version them like a library.
- **Security is a property of the whole pipeline** (least-privilege role + remote locked state + no secrets in state + policy gates), not one setting.
