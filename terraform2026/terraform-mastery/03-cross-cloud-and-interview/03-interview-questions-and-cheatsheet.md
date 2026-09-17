# Cross-Cloud 3 — Interview Questions & Cheat Sheet

> **⏱️ Time to complete: ~60 min** (read + answer the Q&As out loud from memory)

## 3.1 Core Terraform (basic → advanced)

**Q: What is Terraform and how does it work?**
Declarative IaC. You describe the *desired state* in HCL; Terraform builds a **dependency graph**, computes a **plan** (diff of current → desired), and **applies** it. It's **idempotent** (apply twice = no change) and tracks resources in **state**.

**Q: What is state? Why is it important? What are its risks?**
A file mapping **resource address → cloud resource id + attributes**. It's how Terraform knows what it created and computes diffs. Risks: it contains **secrets** (passwords/keys), it can be **corrupted**, and it can cause **conflicts** if two runs share it. Mitigations: **remote backend with locking**, encryption, no secrets in state, `state rm`/`mv` surgery.

**Q: Local vs remote backend. Why remote?**
Remote (S3/Azure Blob/TFC) = shared, **locked**, encrypted, versioned, auditable. Local = single machine, no lock, plaintext. Production is always remote.

**Q: What's a provider? How do you version one?**
A plugin that knows one cloud/API. Declare in `required_providers` with a **version constraint** (`~> 5.0`); `init` downloads it and pins it in **`.terraform.lock.hcl`** (commit that).

**Q: `count` vs `for_each`? When does one cause a problem?**
`count` = index-based (N identical). `for_each` = key-based (stable identity). **Problem:** deleting a middle `count` item shifts keys → **unexpected replacement**. Use `for_each` with stable keys (map/list of strings), never a `set` for `for_each` keys.

**Q: What is `dynamic` used for?**
Rendering a **repeated block** from data (e.g. NSG rules, S3 lifecycle rules) with `for_each` over a list; `for_each = []` → block omitted.

**Q: Explain `lifecycle` meta-arguments.**
- `prevent_destroy` = never destroy (data safety).
- `create_before_destroy` = replace by creating first (zero-downtime).
- `ignore_changes` = don't re-apply certain attributes (owned elsewhere).

**Q: What are data sources? When do you use them?**
`data` blocks that **read** live cloud state at plan time. Use for: existing resources, current identity (account/tenant/AMI), cross-stack references. Note: values can be "known after apply" (can't be `for_each` keys).

**Q: How do you import an existing resource?**
Define it in config (matching the real one) + `terraform import <addr> <id>` (or an `import {}` block). Config must **match** or plan shows a big diff. `terraform destroy` will **delete** it after import.

**Q: What are `moved` and `removed` blocks?**
`moved` = preserve state identity across a refactor (no destroy/create). `removed { from_state = true }` = forget a resource without deleting it.

**Q: What's the difference between a `module` and a `provider`?**
A **module** = reusable group of resources (your code). A **provider** = the cloud plugin (the API client). Modules *use* providers.

**Q: How do you pass provider config into a child module?**
It flows **down** automatically (0.13+). To force a specific (aliased) provider: `providers = { aws = aws.network }`.

**Q: What's an alias? Give a use case.**
Multiple provider configs with different auth/region/account. Use: **multi-account** (AWS `assume_role`) or **multi-region**.

**Q: What is drift? How do you handle it?**
Out-of-band changes (console edits). Every `plan` does an implicit **refresh**. Detect with a scheduled **`plan -refresh-only`** → alert → fix the code (or `state rm`).

**Q: How do you handle secrets?**
Never in code/`tfvars`/state. Use a **secrets manager** (AWS Secrets Manager / Azure Key Vault) via a **data source**, or `random_password` stored in the manager. Mark variables `sensitive` (display-only masking).

**Q: What's `terraform test`?**
Unit tests in `.tftest.hcl` (variables + assertions + plan/apply), run in isolated state — safe in CI. (Introduced 1.6; check current status.)

**Q: When (and when not) would you use `-target`?**
Quick local debugging. **Never** in production/CI — it breaks whole-graph consistency. Use `-replace` for targeted recreation.

**Q: Provisioners — pros/cons?**
Run commands at create/destroy. Cons: **not re-run on update**, not idempotent, secrets leak. Prefer declarative resources / AMIs / extensions.

## 3.2 AWS-Specific

**Q: VPC flow for a 3-tier app.**
Public subnets (IGW route) → ALB; private subnets (NAT route) → app; isolated DB subnets (no 0.0.0.0/0). SGs: ALB (80/443) → web (80 from ALB) → DB (5432 from web). VPC endpoints for S3/SM.

**Q: Security Group vs NACL?**
SG = **stateful**, **ENI-level**, allow-only. NACL = **stateless**, **subnet-level**, allow+deny, `rule_no` (lowest wins). SGs are the workhorse.

**Q: ALB vs NLB?**
ALB = **L7** (HTTP/HTTPS, path/host routing, TLS). NLB = **L4** (TCP/UDP, **static IP**, ultra-low latency).

**Q: What is RDS `multi_az`?**
A **synchronous standby** in a second AZ (HA, ~2× cost). Failover is automatic.

**Q: How do you give an EC2 instance permissions?**
**Instance profile** → **IAM role** (trusted by `ec2.amazonaws.com`) → policies. Keyless (no keys on the instance).

**Q: Cross-account role assumption — the pattern?**
Target role's trust policy allows the source principal **+ `Condition sts:ExternalId`**; source assumes with the matching `external_id` (confused-deputy defense).

**Q: S3 bucket attributes — why separate resources?**
`aws_s3_bucket` + `_versioning` + `_lifecycle_configuration` + `_policy` + `_website_configuration` + `_replication_configuration` — each managed/permissioned independently.

**Q: How would you make S3 private but let CloudFront read it?**
**Origin Access Control (OAC)** + a bucket policy allowing the OAC; keep **public access block** on. (Certs in **us-east-1**.)

## 3.3 Azure-Specific

**Q: Subscription vs Resource Group vs Resource.**
Subscription = billing + access boundary (you auth to it). **RG** = logical container; resources are **1:1 with an RG** (can't move in place). Resource = a VM/VNet/etc. (has a location).

**Q: NSG evaluation order?**
Rules by **priority (100→4096, lower first)**; **first match wins** (Allow or Deny); default-deny inbound, default-allow outbound. Subnet NSG + NIC NSG both apply.

**Q: Managed Identity — system vs user-assigned?**
**System** = created with + lives/dies with the resource. **User-assigned** = standalone, shared by many resources. Both = keyless (no secrets). Preferred over embedded SPs/keys.

**Q: RBAC roles you know?**
**Owner** (full + manage access), **Contributor** (manage resources, not access), **User Access Administrator** (grant roles), **Reader** (read). Granting a role assignment needs **User Access Administrator/Owner** (Contributor can't).

**Q: LB vs Application Gateway?**
LB = **L4** (TCP/UDP, like AWS NLB, static IP). **App Gateway** = **L7** (path/host routing, TLS termination, **WAF**, dedicated subnet; v2 SKU is elastic).

**Q: Azure SQL — how do you make it secure?**
**Firewall** (restrict to app subnet) or **Private Endpoint**; **managed identity** auth (keyless); **`zone_redundant`** for HA; TLS 1.2.

**Q: Why is `features {}` required in the azurerm provider?**
It tunes **per-resource-type behavior** (e.g. key vault retention, deploy mode). v4 = `required_features { features {} }`; v5 = top-level `features {}`.

**Q: What changed in azurerm v5?**
Top-level `features {}`; **resource providers not auto-registered** by default (`resource_provider_registrations = "none"`) — set `legacy` to keep v4 behavior.

## 3.4 Scenario Questions

**Q: A resource is "stuck" (plan shows it replacing every time). How do you debug?**
1. `terraform show -json` on the plan → read the diff. 2. Look for a **non-idempotent** attribute (`uuid()`/`random` in an arg, a `remote-exec` change, a cloud default you didn't set). 3. Fix the source or add `ignore_changes` (deliberately). 4. Re-plan until clean.

**Q: You need to rename a module in code without destroying resources.**
Use a **`moved`** block (`from` → `to`). Plan confirms the identity is preserved (no destroy/create).

**Q: Two people hit a state-lock error. What do you do?**
Wait for the other run to finish. If it's **dead** (crashed), verify (timestamp/user) → `terraform force-unlock <id>`. **Never** force-unlock a live run.

**Q: You must rotate the RDS password without downtime.**
Store it in **Secrets Manager** (or Key Vault); the app reads it at runtime (or via a rotation trigger). Change the secret → app picks it up (redeploy/restart). Avoid hardcoding in state where possible.

**Q: How would you structure a multi-account AWS Terraform setup?**
Provider **aliases** (one per account, `assume_role` + `external_id`). **One state per account/service**. Shared resources via S3 bucket policy / RAM. Verify with `data.aws_caller_identity` per alias.

**Q: The same app must go to dev, staging, prod. How?**
**Shared modules** (versioned) + **three root modules** (one per env) each with its **own state** + `terraform.tfvars`. `local.prod` gates (multi_az, deletion_protection, force_destroy). PR-gated plans; prod = approval.

## 3.5 Cheat Sheet

### CLI (the 20 you'll use daily)
```bash
terraform init            # bootstrap + backend
terraform validate        # schema check (after init)
terraform fmt -check -recursive   # check formatting
terraform plan -out=p     # save the plan
terraform apply p         # apply that plan
terraform apply -auto-approve   # CI only
terraform destroy         # tear everything down
terraform plan -detailed-exitcode   # CI: exit 2 = changes
terraform plan -refresh-only        # drift check
terraform apply -replace=<addr>     # force replace
terraform state list|show|mv|rm     # state surgery
terraform force-unlock <id>         # break a stuck lock
terraform output [-raw <name>]      # read outputs
terraform console         # REPL
terraform graph           # dependency graph
terraform test            # run the tests
terraform import <addr> <id>        # import an existing resource
terraform show -json      # inspect state/plan as JSON
terraform version         # the version
```

### AWS provider block
```hcl
provider "aws" {                      # configure the AWS provider
  region  = var.region                # target region
  profile = "admin"                   # the shared-credentials profile
  default_tags = {                    # tags applied to everything
    Project = "x"                      #  project
    Environment = var.environment      #  environment
    ManagedBy = "terraform"            #  managed-by
  }
  assume_role { role_arn = var.role_arn; external_id = var.external_id }   # cross-account role
}
```

### Azure provider block
```hcl
provider "azurerm" {                  # configure the Azure provider
  client_id = var.client_id           # the SP's app id
  client_secret = var.client_secret   # the SP's secret
  tenant_id = var.tenant_id           # the tenant
  subscription_id = var.subscription_id   # the subscription
  features { key_vault { soft_delete_retention_days = 90 } }   # the features block
}
```

### The "always verify" data sources
```hcl
# AWS
data "aws_caller_identity" "me" {}      # which account am I in
data "aws_region" "current" {}          # which region am I in
# Azure
data "azurerm_client_config" "current" {}  # which client/tenant/subscription am I in
```

### Idempotency debugging
```bash
terraform plan -out=p -json | jq '.[] | select(.resource_addr != null) | {a:.resource_addr, c:.change.actions}'   # list every resource that would change
```

### The 5 laws (say them in any interview)
1. **Declarative** — describe the end state, not the steps.
2. **State is sacred** — remote, locked, encrypted, no secrets.
3. **Idempotent** — second plan is empty.
4. **Plan before apply** — always read the diff.
5. **Modules over copy-paste** — reuse, version, encapsulate.
