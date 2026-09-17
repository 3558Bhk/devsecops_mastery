# 09 · Infrastructure as Code (Terraform / OpenTofu)

Core for DevOps, Cloud and Platform roles. The senior differentiators are **state management, module design, drift, and the "what Terraform is bad at" conversation.**

*Versions referenced: Terraform 1.15.x (BUSL 1.1, HashiCorp/IBM), OpenTofu 1.12.x (MPL 2.0, Linux Foundation / CNCF since April 2025). OpenTofu adds built-in **state encryption**, **provider `for_each`**, **native S3 state locking without DynamoDB**, and **dynamic `prevent_destroy`**. Both speak the same HCL, providers and state format.*

---

## 🟢 Basic

### 1. What is IaC, and what does it actually buy you?
Managing infrastructure through **declarative, version-controlled, machine-readable definitions** rather than consoles and shell scripts.

**The real benefits (in order of value):**
1. **Reproducibility** — identical environments every time; "it works in staging" becomes meaningful. Also the only sane path to DR: rebuild a region from code in an hour instead of archaeology over a week.
2. **Review and audit** — infrastructure changes go through PRs: diff, discussion, approval, blame, history. Answers "who opened port 22 to the world and when" in one command.
3. **Speed and self-service** — a team provisions a compliant environment in minutes from a module instead of filing a ticket.
4. **Consistency at scale** — 200 accounts/services built the same way, with the same guardrails.
5. **Documentation that can't rot** — the code *is* the description of what exists (unlike a wiki).
6. **Reduced human error** — no click-ops typos, no half-configured resources, no forgotten settings.
7. **Cost visibility** — you can read, count, and (with Infracost) price the change before applying.

**What IaC does *not* give you:** correctness (a wrong design, codified, is repeatably wrong), safety (an `apply` can destroy production), or an understanding of *why* (comments and ADRs still matter).

**Declarative vs imperative:** declarative says *what* the end state is; the tool computes the diff and the steps. Imperative (shell scripts, Ansible's task lists, CloudFormation-ish step scripts) says *how*. Declarative is **idempotent by construction** — running it twice converges instead of duplicating. That's the fundamental reason Terraform beat script-based provisioning.

**Where each tool fits:**
| Tool | Model | Best for |
|---|---|---|
| **Terraform / OpenTofu** | Declarative, own state, cloud-agnostic | Cloud resource lifecycle (the "what exists") |
| **Pulumi** | Declarative via general-purpose languages (TS/Python/Go) | Complex logic, teams that hate HCL, real programming constructs |
| **CloudFormation / ARM-Bicep / Deployment Manager** | Declarative, provider-native | Single-cloud, first-class support for new services, no external state |
| **Crossplane** | Declarative **inside Kubernetes**, CRDs + controllers | Platform teams wanting infra as K8s API objects, composed by operators |
| **Ansible** | Imperative-ish, agentless, mostly idempotent | **Configuration** inside machines, package installs, app deploy |
| **Chef/Puppet/Salt** | Agent-based config management | Long-lived VM configuration drift |
| **Helm / Kustomize** | Templating/patching for K8s manifests | In-cluster resources (not a lifecycle tool) |

**The line that scores:** "Terraform manages the *existence* of resources; Ansible manages the *configuration inside* them. With immutable infrastructure and containers the second category mostly disappears — which is why Terraform + images + Kubernetes covers nearly everything now."

### 2. Terraform workflow and lifecycle
```
terraform init      # download providers/modules, initialise the backend
terraform validate  # syntax + internal consistency (no cloud calls)
terraform plan      # read state + refresh real infra + compute the diff  → NO CHANGES MADE
terraform apply     # execute the plan (or apply a saved plan file)
terraform destroy   # tear down (order-aware)
```
Plus: `fmt` (canonical formatting — run in CI), `state list/show/mv/rm/import/pull/push`, `providers lock` (multi-platform provider hashes), `graph`, `console`, `test` (the native test framework), `metadata functions`.

**The lifecycle of a managed resource:**
1. **Create** — not in state, exists in config → create it, write to state.
2. **Update in place** — in both, attributes differ but the change is mutable → call the update API.
3. **Force replacement (destroy+create)** — the changed attribute is `ForceNew` (e.g. an RDS instance's `engine`, an EC2 instance's `ami`, most name/region changes) → **Terraform destroys and recreates it.** ⚠️ **This is the single most dangerous thing in a Terraform plan**, and `plan` shows `-/+ destroy and then create replacement`. On a stateful resource this means **data loss**. Learn to scan for `-/+` before anything else.
4. **Destroy** — in state, not in config → delete.
5. **Import** — exists in reality, not in state → `terraform import` (or, in modern Terraform, an `import` **block** in config, which is plan-able, reviewable and repeatable — strictly better).
6. **Forget** — in state, should be managed elsewhere → `terraform state rm` (leaves the real resource untouched).

**Refresh semantics:** `plan` refreshes state from the API by default. `-refresh=false` skips it (faster, but the plan may be wrong). **Drift detection** is `plan -refresh-only`, which updates state without proposing config changes — use it to find out-of-band modifications.

### 3. Providers — versions, aliasing, and locking
```hcl
terraform {
  required_version = ">= 1.9, < 2.0"        # constrain the CLI
  required_providers {
    aws = {
      source  = "hashicorp/aws"             # registry namespace/name
      version = "~> 6.0"                    # ~> = allow 6.x, not 7.0
    }
  }
  backend "s3" {
    bucket         = "acme-tf-state"
    key            = "prod/network/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "acme-tf-locks"         # OpenTofu 1.12+/AWS provider: native S3 locking, no DynamoDB needed
  }
}
```
- **Always pin provider versions.** Unpinned = a new major provider release can break your plan on any `init -upgrade`, with no code change on your side. This is a real, repeated incident source.
- **`~> 6.0`** allows ≥6.0 <7.0. **`~> 6.1.2`** allows ≥6.1.2 <6.2.0. `= 6.1.2` is exact.
- **`terraform providers lock -platform=linux/amd64 -platform=darwin/arm64`** writes `.terraform.lock.hcl` with per-platform hashes — **commit it**, or macOS developers and Linux CI will disagree and CI will fail with checksum errors.
- **Provider aliasing** for multi-region/multi-account:
  ```hcl
  provider "aws" { region = "eu-west-1" }
  provider "aws" { alias = "us_east_1"; region = "us-east-1" }
  resource "aws_s3_bucket" "dr" { provider = aws.us_east_1; ... }
  ```
- **Provider `for_each`** (OpenTofu 1.9+) — configure a set of provider instances dynamically (e.g. one per region) instead of hand-writing aliases. Genuinely useful for multi-region modules; a real OpenTofu advantage.
- **Meta-arguments:** `depends_on` (explicit ordering — use sparingly; Terraform infers most dependencies from references, and an unnecessary `depends_on` reduces parallelism and can create cycles), `provider`, `count`/`for_each`, `lifecycle`.

### 4. State — what it is and why it matters so much
`terraform.tfstate` is a JSON mapping of **config → real resource IDs and attributes**. It contains:
- Resource addresses, provider metadata, and **attribute values** — including things you can't derive from config (the generated ID, the current status).
- **Sensitive values** (passwords, private keys) — often **in plaintext** unless encrypted. **This is the #1 state security issue.**
- Dependencies between resources (used to order destroy).

**Why state is necessary:** Terraform must know what it manages to compute a diff, to avoid recreating things, to map config to real IDs, and to destroy in dependency order. CloudFormation avoids external state by using the provider's own stack records; Crossplane keeps state as CRs; Terraform keeps it in a file. **Different trade-offs, and knowing why CloudFormation doesn't need one is a good follow-up answer.**

**Backend requirements:**
| Requirement | Why |
|---|---|
| **Remote** (S3, GCS, Azure RM, Terraform Cloud, HTTP) | Shared across the team; local state means "works on my machine" and lost state |
| **Encrypted at rest** | It contains secrets. S3 SSE-KMS, or **OpenTofu's built-in state encryption** (client-side, before upload — strictly better, since the plaintext never touches storage) |
| **Versioned** | Recovery from corruption/accidental overwrite. **Enable S3 versioning — this has saved many teams** |
| **Locked** | Concurrent applies corrupt state or duplicate resources. DynamoDB lock, or native S3 locking, or the platform's locking |
| **Access-controlled** | Read access to state ≈ read access to every secret in your infra. **Tight IAM: state bucket readable only by the platform role, not by every engineer** |
| **Backed up / DR-tested** | Losing state without a backup means re-importing hundreds of resources by hand |

**State hygiene rules:**
- **Never commit `terraform.tfstate` to Git** (secrets + merge conflicts that will destroy your infra).
- **One state file per independently-deployable unit** (see Q11) — not one giant state.
- **Never edit state by hand** except via `terraform state mv/rm/import`.
- **`terraform state pull` / `push`** for migration; `terraform init -migrate-state` for backend changes.
- **If state is lost:** resources still exist; re-associate with `import` blocks (plan-able) rather than `terraform import` (imperative, error-prone at scale). Tools like `terraformer` help but are unreliable — treat generated code as a starting point.

### 5. Variables, outputs, locals — and the right way to use each
```hcl
variable "instance_type" {
  description = "EC2 instance type for the app tier"       # ALWAYS describe — it's the docs
  type        = string
  default     = "t3.medium"
  nullable    = false
  validation {
    condition     = can(regex("^t3\\.(small|medium|large)$", var.instance_type))
    error_message = "instance_type must be one of t3.small|medium|large."
  }
}
variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true                                        # masked in plan/output
}
locals {
  common_tags = { Environment = var.env, Team = "platform", ManagedBy = "terraform" }
  name        = "${var.project}-${var.env}"
}
output "endpoint" {
  description = "Service endpoint URL"
  value       = aws_lb.main.dns_name
}
output "db_password" {
  value     = var.db_password
  sensitive = true                                          # never output secrets anyway
}
```
**Rules:**
- **`variable`** = module input (parameters). **`output`** = module result. **`local`** = internal computation/naming (don't over-use; a wall of locals is unreadable).
- **`sensitive = true` masks values in CLI output but does NOT encrypt them** — they're still in state, and still visible with `terraform state pull` or `TF_LOG=TRACE`. **The only real fix is not to put secrets in Terraform at all** (see Q14).
- **Validation blocks** are the cheapest quality win — fail early with a clear message instead of a confusing API error 3 minutes into an apply.
- **Variable precedence** (highest last): `TF_VAR_*` env vars → `*.auto.tfvars` (alphabetical) → `-var-file` on the CLI → `-var` on the CLI. And `terraform.tfvars` is loaded automatically. **Knowing precedence matters because a stray `.auto.tfvars` silently overrides things.**
- **Never commit `terraform.tfvars` with secrets.** Commit `terraform.tfvars.example`.

### 6. `count` vs `for_each`
```hcl
# count — index-based
resource "aws_subnet" "this" {
  count = length(var.subnet_cidrs)
  cidr_block = var.subnet_cidrs[count.index]
}
# for_each — key-based  ← almost always better
resource "aws_subnet" "this" {
  for_each   = toset(var.availability_zones)
  cidr_block = var.cidrs[each.key]
}
```
**Why `for_each` wins:**
- Addresses are `aws_subnet.this["eu-west-1a"]` (stable, readable) instead of `aws_subnet.this[2]` (positional).
- **Removing an item from the middle of a `count` list destroys and recreates everything after it** — because index 2 becomes what was index 3. This is a **data-loss-class bug** and the classic reason to prefer `for_each`.
- `for_each` requires **a map or set of strings known at plan time**. It cannot take a list of objects directly (use `{ for x in var.list : x.name => x }`), and cannot use values **unknown until apply** (e.g. a computed resource attribute) — that's a hard limitation, and the error message is confusing. `count` *can* use unknown values (with `count = var.enabled ? 1 : 0`).

**Gotchas:**
- **`count = 0` vs `for_each = {}`** are the "disabled" idioms; converting between them requires `terraform state mv` gymnastics (`aws_x.y[0]` → `aws_x.y["key"]`).
- **`for_each` over a resource's computed attribute** is not allowed → restructure so the keys are known at plan time (e.g. pass the AZ list as a variable, not derived from a created VPC).
- Splat expressions (`aws_subnet.this[*].id`) and `for` expressions (`[for s in aws_subnet.this : s.id]`) for outputs.

---

## 🔵 Advanced

### 7. Modules — design principles
```
modules/
  vpc/                 # reusable, composable, single responsibility
    main.tf  variables.tf  outputs.tf  versions.tf  README.md
    examples/basic/    # a runnable example IS the documentation and a test
    tests/             # terraform test files
envs/
  prod/  staging/  dev/
    main.tf            # composes modules with env-specific values
    backend.tfvars
```
**Principles:**
1. **A module is an API.** Its variables are parameters, its outputs are the return value. Design for the *caller*, not for your current use.
2. **Single responsibility, composable.** `vpc`, `eks`, `rds-postgres`, `s3-website` — not `everything`. Small modules compose; big ones get forked.
3. **Sensible defaults, required inputs only where they matter.** A module with 60 variables and no defaults is unusable; one with 3 and hidden magic is inflexible. **Aim for: every variable has a default that's safe for a new caller, and the outputs expose everything a downstream module might need.**
4. **No hardcoded names/regions/accounts.** Everything derived from variables.
5. **Outputs expose the identifiers** other modules need (`vpc_id`, `private_subnet_ids`, `security_group_id`) — this is how composition works without `depends_on` hacks.
6. **Version your modules.** Git tags (`v1.4.2`) or a private registry. **Pin consumers to a version** (`version = "~> 1.4"`), never to a branch. An unpinned module is a time bomb: someone else's merge changes your infra.
7. **`README` + `examples/` + tests.** A module without a runnable example will be used incorrectly.
8. **Stability promise**: changing a variable's type or removing an output is a breaking change → major version bump. Document the migration.
9. **Prefer published community modules for hard problems** (terraform-aws-modules/vpc, /eks, /rds) — they encode edge cases you'd otherwise discover in production. But **read them**; they're configurable to the point of complexity, and you own the result.
10. **Don't over-modularise**: a module wrapping a single resource with 8 variables is worse than the resource. The test: does this encapsulate a decision or a set of invariants that would otherwise be repeated?

**Anti-patterns:** nested modules 4 deep (unreadable plans, hard to trace), modules that `terraform apply` other modules (no), modules with `count` inside that callers can't predict, "god modules" with 200 variables, and **module duplication via copy-paste instead of versioning** (200 copies of a slightly different VPC module is the normal failure state of an unmanaged platform).

### 8. `lifecycle` meta-argument — the four knobs
```hcl
resource "aws_db_instance" "primary" {
  # ...
  lifecycle {
    prevent_destroy           = true            # error if the plan would destroy it
    ignore_changes            = [tags, description]   # don't reconcile these attributes
    create_before_destroy     = true            # for zero-downtime replacement
    replace_triggered_by      = [aws_iam_role.x]      # explicit replacement trigger
  }
}
```
- **`prevent_destroy = true`** — the guardrail for anything stateful (databases, S3 buckets with data, EBS volumes). **Caveat everyone forgets:** it's evaluated at plan time and can be bypassed by *removing the resource from config* in some workflows, and it does **nothing** against `terraform destroy` in older versions / against a determined operator with `state rm`. **OpenTofu 1.12 adds dynamic `prevent_destroy`** (a condition, e.g. only in prod). Treat it as a seatbelt, not a firewall — pair it with IAM deny policies and S3 object lock.
- **`ignore_changes`** — for attributes managed by another system (console-applied tags, auto-generated descriptions, ASG desired capacity managed by an autoscaler). **Overuse is a smell**: it silently creates drift you'll never see. The classic legitimate use: `ignore_changes = [desired_capacity]` on an ASG so autoscaling decisions aren't reverted on every apply.
- **`create_before_destroy = true`** — create the replacement first, then destroy the old. Essential for zero-downtime replacement of things like security groups, load balancers, or DNS records. **Caveat:** it fails if the new and old resources conflict (duplicate names, unique constraints) — then you need `destroy_before_replace` semantics or a rename.
- **`replace_triggered_by`** — explicit, plan-visible replacement (e.g. recreate all EC2 instances when the AMI module changes). Better than the old `null_resource` + `triggers` hacks.

### 9. Drift — detection and response
**Drift** = the real infrastructure differs from the state/config. Causes: console changes, another tool (CloudFormation, a script, an operator), a teammate with a different state file, provider-side defaults changing, **resources deleted externally**, or a failed/partial apply.

**Detection:**
```bash
terraform plan -detailed-exitcode      # exit 0 = no changes, 1 = error, 2 = changes present
terraform plan -refresh-only           # update state to match reality WITHOUT proposing config changes
terraform show -json | jq ...          # machine-readable diff for automation
```
Run `-detailed-exitcode` on a **schedule** (nightly per environment) and alert on exit code 2. Terraform Cloud/Spacelift/env0 do **continuous validation** natively; otherwise a cron job in CI is enough. **Drift you don't detect is drift you'll discover during an incident.**

**Response decision tree:**
1. **Was the change intentional and good?** → **Codify it**: update the config to match reality, then `plan` should be empty. (Or `terraform import` if it's a new resource.) **This is the right answer most of the time** — Git becomes truthful again.
2. **Was it unintentional/bad?** → **Revert it**: `terraform apply` restores the declared state.
3. **Is it a temporary operational override** (e.g. scaled up during an incident)? → Keep it during the incident, then reconcile — and consider `ignore_changes` if the field is legitimately managed elsewhere (autoscaling).
4. **Is it a resource created outside Terraform that should be managed?** → `import` block, then write the config to match.

**The governance point:** "Drift is a symptom of a process problem, not a Terraform problem. If people change the console, it's because the IaC path was too slow, too scary, or they didn't have permission. So the fix is: **deny write access to the console for managed accounts** (SCP/IAM deny on mutating actions, break-glass role with alerting), make the IaC path fast (self-service modules, preview environments, < 30 min from request to resource), and detect+alert on drift so it can't accumulate. Punishing the person who clicked is less effective than removing the ability to click."

### 10. Terraform at scale — state splitting, dependencies, and CI
**The problem with one big state:** every plan refreshes every resource (slow), every apply locks the whole thing (blocked teams), one corrupt state loses everything, blast radius is global, and permissions can't be scoped (state read = all secrets).

**Split by:**
| Boundary | Example |
|---|---|
| **Lifecycle** | Network/foundation (changes rarely) vs app resources (changes daily) |
| **Blast radius** | Separate prod/staging/dev states; separate accounts/regions |
| **Team ownership** | One state per team, matching CODEOWNERS |
| **Change frequency** | IAM/org policy vs workloads |
| **Security** | Secrets-heavy state isolated with tighter IAM |

**Cross-state dependencies:**
- **`terraform_remote_state`** data source — read another state's outputs. Simple, but creates a hidden runtime dependency and requires read access to the other state (secret exposure risk).
- **Explicitly passed variables** — the outputs of stack A become inputs to stack B via the pipeline (`terraform output -json` → feed the next plan). **Better: visible, testable, no cross-state read permission.**
- **Provider-native references** (e.g. looking up a VPC by tag with a data source) — decouples entirely, at the cost of an implicit contract.

**My position:** "I prefer passing outputs through the pipeline over `terraform_remote_state`, because the dependency is explicit in the code and CI, and because remote-state reads grant access to every secret in that state. Where a shared lookup is genuinely needed (a VPC ID), a tagged data source is even better — it removes the coupling completely."

**CI/CD for Terraform:**
```
PR opened
  ├─ terraform fmt -check          (fail on unformatted)
  ├─ terraform init -backend=false
  ├─ terraform validate
  ├─ tflint                        (provider-specific lint, catches real bugs)
  ├─ tfsec / checkov / terrascan   (security policy)
  ├─ terraform plan -out=plan.bin -detailed-exitcode
  │    └─ plan → JSON → post as a PR comment (the diff, human-readable)
  ├─ infracost                     (cost delta on the PR — extremely popular with finance)
  └─ policy check: no "-/+ destroy and then create replacement" on tagged-critical resources
merge to main
  └─ terraform apply plan.bin      ← APPLY THE SAVED PLAN, not a fresh one
```
**Critical detail:** **apply the saved plan file** (`terraform apply plan.bin`). Running a fresh `plan` at apply time can produce a *different* plan if the infrastructure changed between review and merge — so the thing you approved isn't the thing you applied. Saved-plan apply guarantees review fidelity. (Caveat: a saved plan can go stale if the world changes; handle the "plan is not valid" error by re-planning with review.)

**Automation at scale:** Terraform Cloud/Enterprise, Spatelft, env0, Scalr, Atlantis (self-hosted, PR-driven, per-repo locking), or a custom pipeline. **Atlantis is the classic self-hosted answer** — `plan` on PR, `apply` on comment, with locking. **Run the apply from a controlled, audited runner with OIDC-federated cloud credentials**, never from a developer laptop for prod.

**Concurrency:** state locking prevents parallel applies on the same state, but **not** on resources shared across states. Two stacks both touching one security group → last-writer-wins. Design state boundaries so resources have exactly one owner.

### 11. Directory / repo layout patterns
| Pattern | Structure | Pros | Cons |
|---|---|---|---|
| **Env-as-directory** | `envs/{dev,staging,prod}/main.tf` composing shared modules | Simple, visible, per-env state, easy CODEOWNERS | Some duplication across env dirs (mitigated by modules + per-env tfvars) |
| **Component-per-dir** | `components/{vpc,eks,rds}/` × `envs/` | Clear ownership, small states | More directories, more pipeline config |
| **Monorepo** | Everything in one repo | Atomic cross-cutting changes, one pipeline, easy review | Big repo, CODEOWNERS essential, blast radius of a bad merge |
| **Polyrepo** | One repo per component/team | Isolation, clear ownership | Cross-cutting changes need N PRs, version drift |
| **Workspaces (`terraform workspace`)** | One config, multiple named states | Built-in | ⚠️ **Widely considered an anti-pattern for environments**: same config for all envs means you can't have different resource *shapes* per env (e.g. prod has Multi-AZ, dev doesn't), state files are hidden in the backend under workspace prefixes, and it's easy to apply to the wrong workspace. **Use directories, not workspaces, for environments.** Reserve workspaces for genuinely identical parallel things (rare). |

**Say this:** "The single most common Terraform layout mistake is using `terraform workspace` for environments. Environments differ in more than variable values — they differ in resource shape, redundancy, and sometimes which resources exist at all. Workspaces force one config to serve all of them, which leads to `count = var.env == "prod" ? 3 : 1` conditionals everywhere. Directories with shared modules give you per-env state, per-env ownership, and explicit differences."

### 12. Terraform Cloud/Enterprise vs OpenTofu vs alternatives — the 2026 licensing picture
- **Terraform moved to BUSL 1.1** (Aug 2023, HashiCorp; IBM acquired HashiCorp in Dec 2024). BUSL is **not** open source by OSI definition: it permits use but restricts offering Terraform as a competing commercial service. For most internal users, nothing changed practically.
- **OpenTofu** forked immediately (MPL 2.0, Linux Foundation; **CNCF project since April 2025**). Drop-in for most configs: same HCL, same providers, same state format. Migration is typically swapping the binary and running `tofu init -upgrade`; from Terraform ≤1.5, go via OpenTofu 1.6 first.
- **OpenTofu's genuine technical advantages** (not just licensing): **built-in client-side state encryption** (secrets never hit storage in plaintext), **native S3 locking without DynamoDB**, **provider `for_each`** (dynamic multi-region providers), **dynamic `prevent_destroy`**, **early variable/literal evaluation** (variables usable in more places), OCI registry support, experimental OTel tracing.
- **Terraform's advantages:** HashiCorp/IBM commercial support and SLAs, TFC/TFE integration (drift detection, continuous validation, policy-as-code via Sentinel, cost estimation, UI), first-to-market on some features, larger ecosystem of tutorials and third-party tooling, and enterprise procurement comfort.
- **The honest decision framework:** "If you're an internal platform team with no competing-product concerns, both work; choose on (a) whether you need TFC/TFE features, (b) whether state encryption and provider `for_each` solve real problems for you, (c) licence policy at your company — many orgs have a blanket 'no BUSL' rule, which decides it, and (d) which your tooling (Atlantis, env0, Spacelift, CI images) supports best. The migration cost is low and reversible, so this isn't a one-way door — which is worth saying, because people treat it as one."
- **Also mention:** **Crossplane** if you want infrastructure as Kubernetes-native APIs (compositions, claims, GitOps-native, no external state — the state lives in the cluster as CRs). **Pulumi** if your team prefers real programming languages and testing frameworks over HCL. Both are legitimate, and naming the trade-offs shows range.

---

## 🔴 Scenario

### 13. "A `terraform apply` destroyed a production database. What happened, and how do you prevent it?"
**What happened — the likely mechanisms:**
1. **A `ForceNew` attribute changed.** Someone edited `engine_version` (fine, in-place), `identifier` (**force replacement**), `storage_type`, `allocated_storage` below the current value in some providers, `db_subnet_group_name`, or the instance class in a way that requires replacement. The plan said `-/+ destroy and then create replacement` and **nobody read the plan**. This is the overwhelmingly most common cause.
2. **`count` → `for_each` migration (or list reordering)** shifted resource addresses, so Terraform saw "old resource gone from config, new resource appeared" → destroy + create. Address changes are destroys unless you `state mv`.
3. **The resource was removed from config** (a module refactor, a variable default flipping `count` to 0, a file not included because of a `*.tf` rename) → Terraform destroys anything in state but not in config.
4. **State pointed at the wrong environment** — a wrong workspace, a wrong backend key, or `TF_VAR_env=prod` in a dev run. Terraform then "corrected" prod to match dev config.
5. **A module version bump** changed a default or a resource address internally.
6. **`terraform destroy` run against the wrong directory/state.**
7. **A partial failure** left the DB deleted but the state inconsistent, and the retry made it worse.

**Immediate response:**
1. **Stop.** Don't run more Terraform. Every subsequent apply makes recovery harder.
2. **Preserve evidence**: the plan output/JSON, the state before and after (`terraform state pull` — and S3 **versioning** gives you the previous state file), the CI logs, the git diff.
3. **Recover the data**, in order of preference:
   - **Automated backups / snapshots**: RDS retains a final snapshot on deletion **if `skip_final_snapshot = false`** (and `final_snapshot_identifier` was set). Restore from it → new instance → re-point the app. **This is why `skip_final_snapshot = true` is a career-ending default.**
   - **Point-in-time recovery** to the moment before deletion.
   - **Cross-region/replica** if one existed.
   - **Deletion protection**: RDS `deletion_protection = true` blocks API deletion — but note **Terraform can still disable it in the same apply that destroys**, unless you also have an IAM/SCP deny. So: `prevent_destroy` **and** `deletion_protection` **and** an **SCP denying `rds:DeleteDBInstance`** except for a break-glass role. Layers, not one control.
4. **Restore service** from the recovered snapshot, verify data integrity, then fix the config so state matches reality.

**Prevention — the layered answer:**
| Layer | Control |
|---|---|
| **Code** | `prevent_destroy = true` on all stateful resources; `skip_final_snapshot = false` with a deterministic `final_snapshot_identifier`; `deletion_protection = true`; backup retention ≥ 14 days; multi-AZ; **S3 object lock / versioning for buckets** |
| **Plan review** | CI **fails the build** if the plan contains `-/+ destroy and then create replacement` for any resource with a `critical` tag — automated, not dependent on a human reading 4,000 lines. Post the plan summary as a PR comment with **destroy counts highlighted** |
| **Human review** | Required review on prod config; a checklist question: "does this plan destroy anything?" |
| **Process** | Apply the **saved plan**, not a fresh one; never apply prod from a laptop; break-glass applies require a second person and are logged |
| **Cloud-level** | **SCP/IAM deny** on `rds:DeleteDBInstance`, `s3:DeleteBucket`, `ec2:DeleteVolume` for the Terraform role, with a separate, audited break-glass role. **This is the control that actually works even when the code and the reviewer both fail** |
| **State safety** | S3 versioning + object lock on the state bucket; `prevent_destroy` in OpenTofu can be dynamic per environment |
| **Recovery readiness** | **Tested restores.** A snapshot you've never restored is a hypothesis. Schedule quarterly restore drills and measure RTO |
| **Blast radius** | Small states per component, so a bad apply can't reach everything |

**The closing line:** "`prevent_destroy` is a seatbelt — it stops the common case, but it lives in the same file as the thing that destroys the resource, so a determined change removes both. The control that actually holds is an **SCP denying the destructive API call** on the Terraform role, because it's outside the code being changed. Defence in depth means the layer that survives a mistake in every other layer. And then: tested restores, because every prevention control eventually fails."

### 14. "How do you manage secrets with Terraform?" (Very commonly asked; there's a right answer)
**The core problem:** anything you pass into Terraform as a variable lands in **state, in plaintext**, plus potentially in CI logs, plan files, and the `.tfvars` you forgot to gitignore. `sensitive = true` masks *display* only.

**Options, worst to best:**
| Approach | Verdict |
|---|---|
| Hardcoded in `.tf` | ❌ Never. It's in Git history forever (and `git filter-repo` won't undo the exposure — **rotate, don't just delete**) |
| `terraform.tfvars` committed | ❌ Same |
| `-var` on the CLI | ❌ Visible in `ps`, shell history, CI logs |
| `TF_VAR_*` env vars | ⚠️ Better, still in state plaintext and in CI env dumps |
| `sensitive = true` variables | ⚠️ Masks display only; **still plaintext in state** |
| **Encrypted remote state** (S3 + KMS, or **OpenTofu built-in state encryption**) | ✅ Table stakes — encrypts at rest, but anyone with decrypt permission can read every secret |
| **SOPS + age/KMS-encrypted `.tfvars`/YAML in Git** | ✅ Good: encrypted files are committable, decrypt at plan time. Key management via age/KMS. Popular with GitOps |
| **Vault / cloud secret manager as the source, Terraform only *references*** | ✅✅ Best |
| **Terraform creates a *reference*, not the value** | ✅✅ The real pattern |

**The pattern that wins:**
> "Terraform should manage the **existence and permissions** of the secret, not its **value**. Concretely: Terraform creates the Secrets Manager secret with a generated placeholder (or lets the service generate it), grants the *consumer* an IAM role to read it, and the application fetches the value at runtime. The plaintext never enters Terraform, state, Git, or CI logs."

```hcl
# ✅ Terraform manages the container + access, not the value
resource "aws_secretsmanager_secret" "db" {
  name                    = "${local.name}/db"
  recovery_window_in_days = 7
  # No secret_string → AWS generates a random one, and Terraform never sees it
}
resource "aws_iam_role_policy" "app_reads_db_secret" {
  role   = aws_iam_role.app.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.db.arn
    }]
  })
}
# App resolves it at runtime (IRSA/workload identity, External Secrets Operator, or SDK)
```
**Rotation:** Secrets Manager rotation via Lambda, or Vault dynamic secrets (short-lived, generated per request — **the strongest model: there is no long-lived secret to steal**). Terraform configures the rotation policy; it never handles the value.

**For Kubernetes:** Terraform creates the cloud secret + IAM; **External Secrets Operator** syncs it into a Kubernetes `Secret`; the pod mounts it. Terraform never writes the Secret value into Git or state.

**If you must pass a value in:** OpenTofu state encryption (client-side, so plaintext never reaches the backend) + tightly scoped state-read IAM + `TF_VAR_` from an OIDC-fetched short-lived credential + never `-out` a plan file containing secrets to an unencrypted location + scrub CI logs.

**And the audit point:** "Read access to a Terraform state file is equivalent to read access to every secret in that infrastructure. So state-read permissions should be among the tightest in the organisation, and the state bucket should be its own security boundary — which is also an argument for splitting state by sensitivity, not just by lifecycle."

### 15. "Terraform plan takes 12 minutes. Speed it up."
**Measure first:** `TF_LOG=TRACE` is too noisy; use `terraform plan -json` timings, or the **experimental OpenTofu OpenTelemetry tracing**, or the provider-level timing in TFC. Usually the time is dominated by **API read calls during refresh**, not by graph computation.

**Ranked fixes:**
1. **Split the state.** A 2,000-resource state refreshes 2,000 API calls serially-ish (providers parallelise with `-parallelism`, default 10). Splitting into 10 states of 200 resources gives you 10 parallel pipelines and 10× faster individual plans. **This is the biggest win and also fixes locking, blast radius and permissions.**
2. **`-parallelism=N`** — raise it (default 10) if the provider and API rate limits allow. Watch for throttling (`RequestLimitExceeded`, 429s), which makes it slower, not faster. Test empirically.
3. **`-refresh=false`** — skip reading real state. **Only safe when you're confident there's no drift** (e.g. immediately after an apply, or in a pipeline where drift is checked separately on a schedule). Fastest single change, but it can produce a wrong plan.
4. **`-target`** — plan/apply only a subgraph. **Use only for emergencies**: it silently ignores dependencies, can leave the state inconsistent, and Terraform explicitly warns against it in normal operation. Never in CI.
5. **Remove unnecessary `data` sources.** Every `data "aws_..."` is a read at plan time. A module that looks up 15 things "for convenience" costs 15 API calls on every plan. Cache with outputs passed between stacks, or look up once and pass the ID as a variable.
6. **Reduce `depends_on`** — explicit dependencies serialise the graph. Terraform infers ordering from references; an unnecessary `depends_on` destroys parallelism.
7. **Avoid `count`-based fan-out over huge lists** and avoid `for_each` on values that force repeated lookups.
8. **Provider version and HTTP tuning** — newer providers are often faster; keep them pinned and upgraded deliberately. Provider-level retries/timeouts matter if you're being throttled.
9. **Don't plan on every commit for every environment.** Plan only for changed directories (path filters / affected-stack detection). A monorepo that plans 40 stacks on every PR is a self-inflicted problem.
10. **Cache the plugin directory** (`.terraform/`) in CI so `init` doesn't re-download providers every run — often several minutes on its own.
11. **Backend latency**: an S3 backend in a different region from your runner adds seconds per operation. Co-locate.
12. **Consider whether you need a plan at all in that pipeline stage** — `validate` + `tflint` + policy checks catch most issues in seconds; reserve full plans for the merge path and scheduled drift checks.

**Target and framing:** "For a well-split setup I'd expect plans in 20–60 seconds per stack. If a plan takes 12 minutes, the state is too big — that's an architecture problem, and the same split also fixes locking contention, blast radius, and secret exposure. I'd treat slow plans as a leading indicator of a state-design problem, not as something to optimise with `-refresh=false`, which trades correctness for speed."

### 16. "How would you let 30 teams self-service infrastructure without chaos?"
**Design: a paved road with guardrails.**

1. **Curated, versioned modules** for the 10 things teams actually need (VPC/network attachment, EKS workload namespace, RDS Postgres, S3 bucket, SQS queue, ALB target group, DNS record, IAM role for a service, observability bundle). Each: sensible secure defaults, validated inputs, complete outputs, a README, an example, and tests. **Teams consume modules, they don't write raw resources.**
2. **Guardrails in the modules, not in a policy doc**: encryption on by default, public access blocked, logging enabled, retention set, least-privilege IAM templates, required tags injected automatically (team, cost centre, environment, data classification), backup enabled. **A team should have to actively work to build something insecure.**
3. **Policy as code at three points:**
   - **CI**: `tflint`, `checkov`/`tfsec`, `conftest`/OPA on the plan JSON, Infracost with a budget threshold.
   - **Cloud**: **SCPs / Azure Policy / GCP Org Policy** — the layer that holds even if CI is bypassed. Deny: disabling encryption, public S3, `rds:Delete*` on prod, creating resources in unapproved regions, root-user actions.
   - **Runtime**: config/conformance rules (AWS Config, Security Hub) alerting on drift from the standard.
4. **Account/subscription/project-per-team** (or per-environment-per-team) with landing-zone automation: identity federation, network attachment, baseline security, billing tags, log aggregation — all created by a **bootstrap module**. Team A's blast radius is its own account.
5. **Self-service workflow**: a team opens a PR against their own directory in the infra repo (or uses an internal portal / Backstage template / Atlantis) → CI validates + plans + posts the plan and cost → auto-merge if within policy, human review only if the plan touches anything critical or exceeds a cost threshold → apply from a controlled runner with OIDC.
   **The key design decision: which changes are auto-approved?** My answer: anything fully within policy, under a cost threshold, with no destroys, in a non-prod environment → auto-apply. Prod, destructive changes, new resource types, or over-threshold → human review. **Automate the boring 90% so humans can focus on the risky 10%.**
6. **Cost governance**: Infracost on every PR, per-team budgets with alerts, tagging enforced (untagged = auto-remediated or reported), showback dashboards, orphan-resource detection, scheduled teardown of non-prod.
7. **Observability of the platform itself**: pipeline duration, plan failure rate, drift rate per team, module version adoption (are teams on v1.2 or v3.0?), apply frequency, mean time to provision, and support ticket volume. **Module adoption is the metric that tells you whether the paved road is actually paved.**
8. **Versioning and upgrade path for modules**: semver, a changelog, **automated upgrade PRs** (Renovate/Dependabot on module versions), a deprecation policy, and a documented migration for breaking changes. If upgrading a module is painful, teams pin old versions forever and your guardrails rot — **so make upgrades mechanical and, ideally, non-breaking**.
9. **Escape hatches with friction**: teams can write raw resources or use an unsupported module, but it requires a documented justification, extra review, and it's visible on a dashboard. **No escape hatch → shadow IT. No friction → chaos.**
10. **Documentation and support**: a "start here" guide, a working example per module, an office hour, a Slack channel with an SLO, and **the platform team treats teams as customers** — with a roadmap driven by their requests, not by what's fun to build.

**The anti-patterns to name:** a ticket-based infra team (bottleneck at ~15 teams, and it doesn't scale); a wiki of standards nobody enforces; a "golden module" so configurable it's incomprehensible (200 variables); letting every team fork the modules (200 divergent copies); and building a bespoke internal platform UI before the modules are good — **the modules are the product; the UI is packaging**.

---

## Red flags

| Saying / doing this | Costs you |
|---|---|
| Not reading the plan for `-/+ destroy and then create replacement` | The #1 cause of Terraform data loss |
| `count` for a list that might be reordered or shrunk | Destroys/recreates the tail |
| Unpinned provider versions | A provider major breaks your apply with no code change |
| State committed to Git | Secrets in history + destructive merge conflicts |
| Unencrypted remote state | Every secret readable by anyone with state access |
| No state locking | Concurrent applies → corruption/duplicates |
| One giant state file | Slow plans, global blast radius, team contention, secret sprawl |
| `terraform workspace` for dev/staging/prod | Can't vary resource shape per env |
| `skip_final_snapshot = true` on a database | No recovery when it's destroyed |
| `prevent_destroy` as the *only* protection | It lives in the same file as the destroy |
| Secrets passed as Terraform variables when they could be runtime-resolved | Plaintext in state, forever |
| `-target` in CI | Silently incomplete applies |
| `-refresh=false` habitually | Plans that don't reflect reality |
| Applying a fresh plan instead of the reviewed saved plan | You approved something different from what ran |
| Unversioned/unpinned modules | Someone's merge changes your infra |
| Copy-pasted modules instead of versioned ones | 200 divergent copies, no guardrails |
| Overusing `ignore_changes` | Invisible permanent drift |
| No scheduled drift detection | You find drift during the incident |
| Never testing a restore | Your backup strategy is a hypothesis |

## Rapid recall

1. IaC buys reproducibility, review/audit, speed, consistency, and DR — not correctness or safety.
2. Terraform for resource *existence*; Ansible for *configuration inside*; with containers, the second mostly disappears.
3. Lifecycle: create / update-in-place / **force replacement (`-/+`)** / destroy / import / forget. Scan plans for `-/+` first.
4. Pin CLI and provider versions; commit `.terraform.lock.hcl` with multi-platform hashes.
5. State = config↔reality mapping **containing plaintext secrets**. Remote + encrypted (OpenTofu does it client-side) + versioned + locked + tightly IAM-scoped + restore-tested.
6. `for_each` over `count`: stable keys, no tail-destruction on reorder; but keys must be known at plan time.
7. Modules are APIs: single responsibility, safe defaults, rich outputs, versioned + pinned, with examples and tests.
8. `lifecycle`: `prevent_destroy` (seatbelt), `ignore_changes` (drift risk), `create_before_destroy` (zero-downtime replacement), `replace_triggered_by`.
9. Drift: detect on a schedule with `plan -detailed-exitcode`; respond by **codifying** intentional changes and **reverting** unintentional ones; prevent with console write-deny + a fast IaC path.
10. Split state by lifecycle / blast radius / ownership / frequency / sensitivity; pass outputs through the pipeline rather than `terraform_remote_state`.
11. CI: fmt → validate → tflint → checkov/tfsec → plan (saved) → policy-fail on destroys → infracost → **apply the saved plan**.
12. Secrets: Terraform manages the container and the IAM, not the value. Vault dynamic secrets are the strongest model.
13. Slow plans = state too big. Split first; `-parallelism`, fewer data sources, fewer `depends_on`, cache `.terraform/`, plan only changed stacks.
14. Self-service = curated modules with guardrails baked in + policy at CI **and** cloud-SCP level + per-team accounts + auto-apply for the boring 90% + escape hatches with friction + module adoption metrics.

→ Next: [`10-Observability`](../10-Observability/README.md) · See also the full deep-dive in [`Monitoring and Alerting/`](../../Monitoring%20and%20Alerting/README.md)
