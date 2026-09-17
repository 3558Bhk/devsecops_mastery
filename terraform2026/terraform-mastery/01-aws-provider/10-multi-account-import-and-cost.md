# AWS 10 — Multi-Account, Data Sources, Import & Cost

> **⏱️ Time to complete: ~50 min** (read + import one existing resource)

## 10.1 Multi-Account Strategy

### The account layout (a common "AWS control tower"-style org)

| Account | Purpose |
|---|---|
| **Management/Payment** | Org root, billing, SCPs |
| **Security/Log Archive** | Centralized CloudTrail, Config, GuardDuty |
| **Networking/Shared** | Transit GW, shared S3, shared subnets |
| **Workload (per app/team)** | The actual apps (dev/staging/prod) |
| **Data** | Data lake, analytics |

### Implementing it in Terraform = **provider aliases**

```hcl
terraform {                          # the terraform config block
  required_providers {               # declare providers
    aws = {                          # the aws provider
      source = "hashicorp/aws"       # registry address
      configuration_aliases = [      # the aliases you'll define
        aws.network,                  # the network account alias
        aws.data,                     # the data account alias
        aws.security                  # the security account alias
      ]
    }
  }
}

# Each alias = a different account (via assume_role) + region
provider "aws" {                       # workload account (default)
  region = var.region                  # the region
  assume_role { role_arn = "arn:aws:iam::111111111111:role/tf-workload" }   # workload role
}

provider "aws" {                       # network account (aliased)
  alias  = "network"                   # alias name
  region = var.region                  # the region
  assume_role { role_arn = "arn:aws:iam::222222222222:role/tf-network" }   # network role
}

provider "aws" {                       # data account (aliased)
  alias  = "data"                      # alias name
  region = var.region                  # the region
  assume_role { role_arn = "arn:aws:iam::333333333333:role/tf-data" }   # data role
}

# Use them
resource "aws_s3_bucket" "shared" {   # a bucket in the NETWORK account
  provider = aws.network              # use the network-account provider
  bucket   = "shared-222222222222"    # the bucket name
}

resource "aws_dynamodb_table" "orders" {   # a table in the DATA account
  provider = aws.data                 # use the data-account provider
  name     = "orders"                 # the table name
  # ...
}
```

**Key points:**
- **One state can span multiple accounts** (via aliases) — but **prefer one state per account/service** for parallelism + blast radius.
- **Cross-account data sharing** = S3 bucket policy / Lake Formation / RAM (Resource Access Manager).
- **`data.aws_caller_identity`** per alias tells you *which* account you're in (put it in each provider's scope to verify).

### Cross-account role assumption (least privilege)

- Each account has a **terraform role** with a **trust policy** for the pipeline principal (CI OIDC or the management account).
- **`external_id`** on cross-account roles (confused-deputy defense).
- **`source_identity`** = auditable in CloudTrail.

## 10.2 The Data Sources You'll Use Most (AWS)

```hcl
data "aws_caller_identity" "me" {}          # account, arn, user_id
data "aws_partition" "current" {}            # aws | aws-us-gov | aws-cn
data "aws_region" "current" {}               # region name
data "aws_availability_zones" "available" { state = "available" }   # available AZs
data "aws_ami" "ubuntu" { ... }              # AMI lookup
data "aws_vpc" "main" { id = var.vpc_id }    # an existing VPC
data "aws_subnets" "x" { filter { name = "vpc-id"; values = [data.aws_vpc.main.id] } }   # subnets in that VPC
data "aws_s3_bucket" "shared" { bucket = "shared" }   # an existing bucket
data "aws_iam_policy" "admin" { arn = "arn:aws:iam::aws:policy/AdministratorAccess" }   # the admin policy
data "aws_iam_policy_document" "doc" { ... } # build trust/policy JSON
data "aws_ec2_metadata" "current" {}         # instance metadata (when on EC2)
data "aws_secretsmanager_secret_version" "s" { secret_id = var.secret_arn }   # a secret
data "aws_route53_zone" "main" { name = "example.com" }   # a hosted zone
data "aws_kms_alias" "x" { name = "alias/x" }   # a KMS alias
data "terraform_remote_state" "network" {    # read ANOTHER root module's outputs
  backend = "s3"                             # the backend type
  config  = { bucket = "my-tfstate"; key = "network/prod.tfstate"; region = "ap-south-1" }   # where the state lives
}
# use: data.terraform_remote_state.network.outputs.private_subnet_ids
```

**`terraform_remote_state`** = the way to pass values **between separate state files** (e.g. the network stack's subnets into the compute stack). It's read-only and refreshed at plan time.

## 10.3 Importing Existing Resources

```bash
# 1) Define the resource in config (matching the real one)
# 2) Import
terraform import aws_instance.legacy i-0abc123
terraform import module.vpc.aws_vpc.main vpc-0123
# 3) Plan — verify the config matches (fix diffs) — then apply
```

**Declarative (1.5+):**
```hcl
resource "aws_instance" "legacy" {         # the resource to adopt
  ami           = "ami-0123"               # (must match the real instance)
  instance_type = "t3.micro"               # (must match the real instance)
}
import {                                   # the import block
  to = aws_instance.legacy                 # import into this address
  id = "i-0abc123"                         # the cloud resource id
}
```

**Import gotchas:**
- The **config must match** the real resource or plan shows a big "fix" diff.
- `import` into a **module**: `terraform import module.x.aws_vpc.main vpc-...`.
- After import, `terraform destroy` **will delete it** — be deliberate.
- Use `-generate-config-out` to auto-generate the resource block:
  `terraform plan -generate-config-out=imported.tf` (then review + move into proper modules).

## 10.4 State Migration & Refactoring (recap with `moved`)

```hcl
# Moved a resource into a module? Preserve identity:
moved {                                    # a moved block
  from = aws_instance.web                  # the old address
  to   = module.compute.aws_instance.web   # the new address
}

# Dropped a resource intentionally? Don't destroy, just forget:
removed "aws_instance.old" {               # a removed block
  from_state = true                        # remove from state only (leave the cloud resource)
}
```

## 10.5 Cost Management

| Technique | How |
|---|---|
| **`default_tags`** (cost-allocation) | Tag every resource; enable **cost allocation tags** in the billing console. |
| **`for_each`/`count`** | Right-size (don't over-provision). |
| **Spot** | 80–90% cheaper for stateless. |
| **Lifecycle / tiering** | S3 IA/Glacier; stop dev instances (scheduled). |
| **Scheduled scaling** | Scale down nights/weekends. |
| **Infracost** | `infracost break-down` in CI → cost diff per PR. |
| **Terraform Cloud cost estimation** | Built-in per-run estimate. |
| **`tags_all` in alarms** | Track by tag. |

```bash
# Infracost (CI-friendly)
infracost break-down --path environments/prod   # cost per resource
infracost diff   # cost delta vs the last commit
```

**Cost guardrail in CI:** fail the PR if the estimated delta > threshold.

## 10.6 Drift Detection (scheduled)

```bash
# Weekly: refresh + plan (no apply) → alert if there are changes
terraform plan -refresh-only   # detect drift without proposing changes
terraform plan -detailed-exitcode   # exit 2 = drift/changes → page
```

Wire into a scheduler (EventBridge / GitHub Actions cron / TFC) and alert on non-zero exit.

## 10.7 The "AWS Provider" Checklist (before you ship)

- [ ] **Provider pinned** (`~> 5.0`) + `.terraform.lock.hcl` committed.
- [ ] **`default_tags`** set (project/env/managed-by/cost-center).
- [ ] **Guardrails**: `forbidden_account_ids` / `allowed_account_ids`.
- [ ] **Auth**: OIDC (CI) / SSO (dev) — no long-lived keys.
- [ ] **`data.aws_caller_identity`** output to verify account/region.
- [ ] **Encrypted**: EBS, S3 (SSE-KMS), RDS, EFS.
- [ ] **Least-privilege** IAM (roles, not users; external_id cross-account).
- [ ] **`prevent_destroy`/`deletion_protection`** on data-bearing resources (prod).
- [ ] **`force_destroy`/`skip_final_snapshot`** env-gated (dev-only).
- [ ] **Import** existing resources deliberately (and know `destroy` will delete them).
- [ ] **Infracost** / cost guardrail in CI.

## 10.8 Interview Quick Facts

- **Multi-account** = provider **aliases** + **assume_role** (+ `external_id`).
- **`terraform_remote_state`** = read another state's outputs (cross-stack).
- **`import`** = adopt an existing resource (config must match; destroy deletes it).
- **`moved`/`removed`** = safe refactors (preserve identity / forget without deleting).
- **Cost** = tags + spot + lifecycle + scheduled scaling + Infracost/TFC estimates.
- **`data.aws_caller_identity`** = always verify which account you're in.
- **One state per account/service** (not one giant state).
