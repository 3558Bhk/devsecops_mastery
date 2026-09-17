# 7. Advanced Resource Configuration

> **⏱️ Time to complete: ~60 min** (read + build a for_each/dynamic/lifecycle example)

## 7.1 `count` vs `for_each`

```hcl
# count — index-based, ordered
resource "aws_instance" "web" {         # an EC2 instance (repeated by count)
  count    = var.instance_count         # create N instances (N from a variable)
  instance_type = var.sizes[each.index % length(var.sizes)]   # pick a type round-robin by index
}

# for_each — key-based, stable identity
resource "aws_instance" "web" {         # an EC2 instance (repeated by for_each)
  for_each = toset(var.web_names)       # one instance per name (set of names)
  instance_type = var.default_type      # the instance type
  tags = { Name = each.key }            # tag with the key (the name)
}

# for_each with a map = the best pattern for named replicas
resource "aws_instance" "web" {         # an EC2 instance (repeated by for_each over a map)
  for_each = var.web_instances          # { web1 = {type="t3.small"}, web2 = {...} }
  instance_type = each.value.type       # each instance gets its own type
  tags = { Name = "${each.key}" }       # tag with the map key (web1/web2)
}
```

**Decision rules:**
- `count` → when you truly need an *index* (N identical things).
- `for_each` → when each instance has an *identity* (name/key). **Prefer for_each** — keys are stable; `count` keys can shift when you delete a middle item (`web[0]` stays, `web[1]` becomes `web[0]` → **replace storm**).
- **Never** use `count.index` with a set (order is random).
- `for_each` over a **map or list of strings** = stable keys. Over a **set** = stable membership but *unordered* (keys are internal hashes).

> Classic trap: `for_each = { for x in var.list : x => true }` is fine; `for_each = var.list_of_objects` is **not** (keys must be strings).

## 7.2 `dynamic` Blocks (repetitive nested blocks)

Used when a resource takes a **repeated block** (e.g. S3 lifecycle rules, NSG rules, IAM statements) and the list is data-driven:

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "b" {   # lifecycle config for bucket "b"
  bucket = aws_s3_bucket.b.id               # target the bucket

  dynamic "rule" {                           # a dynamic block: repeat the `rule` block
    for_each = var.lifecycle_rules           # once per lifecycle rule object
    content {                                # the body of each generated rule
      id      = rule.value.id                # rule id from the object
      status  = "Enabled"                    # active
      tags    = rule.value.tags              # optional rule tags
      transition {                           # a storage-class transition
        days          = rule.value.days      # after this many days
        storage_class = rule.value.storage_class   # to this class (IA/Glacier/...)
      }
    }
  }
}
```

The same pattern in Azure NSGs:

```hcl
dynamic "security_rule" {                    # a dynamic block: repeat the security_rule block
  for_each = var.rules                       # once per rule object
  content {                                  # the body of each generated rule
    name                       = security_rule.value.name          # rule name
    priority                   = security_rule.value.priority      # 100–4096 (lower = first)
    direction                  = security_rule.value.direction     # Inbound/Outbound
    access                     = security_rule.value.access        # Allow/Deny
    protocol                   = security_rule.value.protocol      # Tcp/Udp/...
    source_port_range          = security_rule.value.source_port   # source port
    destination_port_range     = security_rule.value.dest_port     # destination port
    source_address_prefix      = security_rule.value.src           # source CIDR/prefix
    destination_address_prefix = security_rule.value.dst           # destination CIDR/prefix
  }
}
```

`for_each = []` → block simply doesn't render (no errors). This is how you make optional sub-resources clean.

## 7.3 `lifecycle` Meta-Argument

```hcl
resource "aws_instance" "db" {              # a (database-ish) instance
  ...
  lifecycle {                               # the lifecycle meta-argument block
    # NEVER let Terraform destroy this (production data!)
    prevent_destroy = true                  # destroy is blocked for this resource

    # Replace = create new BEFORE destroying old (zero-downtime swaps)
    create_before_destroy = true            # create-then-destroy ordering

    # Ignore changes to these attributes (managed elsewhere)
    ignore_changes = [                      # list of attributes to stop re-applying
      "ami",                                 # whole attribute (e.g. Packer updates it)
      "user_data",                           # e.g. Ansible owns this
      "tag_specifications",                  # ignore tag specs
      # or a list entry:
      # "block_device_mappings[0].volume_size",
    ]
  }
}
```

- `ignore_changes` is **permanently** ignoring — the config value is never re-applied. Use for attributes owned by another tool (Ansible, cloud automation, cost tools). It does NOT mean "revert on next plan".
- `create_before_destroy` matters for **stateful/serial** resources (DB, LB) where you need the new one running before the old dies.
- `prevent_destroy` is a **safety net** for data-bearing resources — but it also means you can't `terraform destroy` the stack cleanly (you must `state rm` + destroy the shell).

## 7.4 `depends_on` (breaking implicit dependencies)

Terraform builds the graph from **explicit attribute references**. When there's a real dependency you *can't* express as a reference (e.g. "wait for the DB subnet group to exist before the DB", or ordering between modules), use:

```hcl
resource "aws_db_instance" "main" {         # a DB instance
  ...
  depends_on = [aws_db_subnet_group.main]   # explicitly wait for the subnet group
}

module "compute" {                          # a child module
  ...
  depends_on = [module.vpc]                 # module-level: wait for the vpc module
}
```

Rule: **if you can reference an attribute, do it** (clearer graph). `depends_on` is for edges that have no natural reference.

## 7.5 Preconditions & Postconditions (1.2+)

Fail *fast and clearly* instead of letting the cloud reject it:

```hcl
resource "aws_instance" "web" {             # an EC2 instance
  ...
  provisioner "local-exec" { ... }          # (a provisioner, see below)

  precondition {                            # check BEFORE the action
    condition     = var.instance_count > 0 && var.instance_count <= 20   # count in range
    error_message = "instance_count must be 1..20, got ${var.instance_count}."
  }

  postcondition {                           # check AFTER apply, against `self`
    condition     = self.public_ip != ""    # the instance got a public IP
    error_message = "Instance has no public IP; check subnet routing."
  }
}

# module-level precondition
module "db" {                               # a db module
  ...
  precondition {                            # a precondition on the module
    condition     = var.environment == "prod" ? var.approval_token != "" : true  # prod needs a token
    error_message = "Prod DB changes require an approval token."
  }
}
```

- `precondition` is evaluated **before** the action; `postcondition` **after** apply, against `self`.
- They make your config **self-documenting** and CI-friendly.

## 7.6 Provisioners (use sparingly)

Provisioners run commands at create/destroy. They are **last resort** — prefer pure-declarative alternatives.

```hcl
resource "aws_instance" "app" {             # an EC2 instance
  ...
  # Runs on the LOCAL machine at create time
  provisioner "local-exec" {                # execute a command locally
    command = "aws s3 cp s3://cfg/app.conf /tmp/app.conf"   # the command to run
  }

  # Runs ON the REMOTE machine (needs SSH)
  provisioner "remote-exec" {               # execute a command on the instance
    connection {                            # how to reach the instance
      type     = "ssh"                      # over SSH
      user     = "ec2-user"                 # the SSH user
      private_key = file("./ssh/id_rsa")    # the private key file
      timeout  = "10m"                      # connection timeout
    }
    script = "./bootstrap.sh"               # the script to run on the instance
  }

  # Runs at destroy time
  provisioner "destroy" {                   # a destroy-time provisioner
    when    = destroy                       # when to run: at destroy
    on_failure = continue                   # don't abort the destroy on failure
    command = "cleanup.sh"                  # the cleanup command
  }
}
```

**When NOT to use provisioners:**
- If you can express it as a **resource** (e.g. install a package → use an extension/AMI/lambda, not `remote-exec`).
- If it must be **idempotent** and **re-runnable** (provisioners are NOT re-run on in-place updates — a notorious gotcha).
- If it touches **secrets** (they end up in state/plan).

**Better alternatives:** AMIs (Packer), cloud extensions, `null_resource` + local-exec for one-off local tasks, or Terraform **modules** that model the thing declaratively.

## 7.7 `null_resource` (the escape hatch)

A resource with no real cloud counterpart — a **placeholder in the graph** for running arbitrary local logic:

```hcl
resource "null_resource" "notify" {         # a no-op resource (graph placeholder)
  triggers = {                              # a map; changing ANY value replaces the resource
    app_version = var.app_version           # trigger 1: the app version
    env         = var.environment           # trigger 2: the environment
  }

  provisioner "local-exec" {                # run a local command (re-runs on replace)
    command     = "curl -X POST -d version=${var.app_version} ${var.webhook}"   # hit a webhook
    interpreter = ["/bin/bash", "-c"]       # run via bash -c
  }
}
```

- `triggers` (a map) change → the null_resource is **replaced** (destroy+create) → provisioner re-runs. This is how you get "run when X changes".
- Common uses: CI hooks, DNS pre-warming, one-off migrations, ordering glue.
- **Anti-pattern:** using it to "fix" a resource that should be declarative.

## 7.8 Data Sources (reading live cloud state)

```hcl
# The workhorses you'll use constantly
data "aws_caller_identity" "me" {}          # current AWS account/arn/user
data "aws_partition" "current" {}           # current partition (aws/aws-cn/...)
data "aws_region" "current" {}              # current region
data "aws_availability_zones" "available" { state = "available" }  # available AZs
data "aws_ami" "ubuntu" {                   # find an AMI
  most_recent = true                        # the most recent one
  owners      = ["099720109477"]            # Canonical
  filter { name = "name"; values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"] }  # name filter
  filter { name = "virtualization-type"; values = ["hvm"] }  # HVM only
}
data "aws_vpc" "main" { id = var.vpc_id }   # read an existing VPC by id
data "aws_subnets" "private" {              # find private subnets of that VPC
  filter { name = "vpc-id"; values = [data.aws_vpc.main.id] }          # in this VPC
  filter { name = "map-public-ip-on-launch"; values = ["false"] }      # and not public
}
data "aws_iam_policy_document" "assume" { statement { ... } }   # build an IAM policy doc
data "aws_s3_bucket" "shared" { bucket = "shared" }             # read an existing bucket
data "azurerm_client_config" "current" {}   # current Azure identity (client/tenant/sub)
data "azurerm_resource_group" "existing" { name = var.rg_name }  # read an existing RG
data "azurerm_client_config" "c" {
  # client_id, tenant_id, subscription_id
}
data "azurerm_virtual_network" "vnet" { name = "vnet-prod"; resource_group_name = "rg-prod" }  # read a VNet
```

Key behaviors:
- Data sources are **refreshed at plan time** (they read live state).
- Their attributes are **known after apply** in some contexts → can't always be used in `count`/`for_each` keys (those must be known at plan).
- Use data sources for: **importing** existing resources, **cross-stack references** (read another stack's outputs without coupling), **current identity** (account/tenant/subscription).

## 7.9 Importing Existing Resources

Two ways (modern → classic):

### 1) Declarative `import` block (1.5+, preferred)
```hcl
resource "aws_instance" "legacy" {         # define the resource to adopt
  instance_type = "t3.micro"               # (must MATCH the real instance)
  ami           = "ami-0123"               # (must MATCH the real instance)
}

import {                                   # the import block
  to = aws_instance.legacy                 # import INTO this resource address
  id = "i-0abc123def456"                   # the cloud resource id
}
```
Run `terraform plan -generate-config-out=imported.tf` (for `to` without a full resource) or just `terraform plan` (with a full resource defined) → then `apply` writes it into state.

### 2) CLI `terraform import`
```bash
terraform import aws_instance.legacy i-0abc123def456
# then run `terraform plan` — the config must MATCH the imported attributes or you'll see diffs
```

**Import gotchas:**
- The resource **must** be defined in config *and* its attributes must **match** the real one (or plan shows a big diff to "fix" it).
- Import into a **module**: `terraform import module.vpc.aws_vpc.main vpc-0123`.
- After import, `terraform destroy` **will delete it** — know what you're importing.
- Use `import` blocks for **drift recovery**: someone deleted your state entry but the resource lives on.

## 7.10 `moved` and `removed` Blocks (1.1+)

```hcl
# Refactor: resource moved to a new module — preserve state identity
moved {                                    # a moved block
  from = aws_instance.web                  # the OLD address
  to   = module.compute.aws_instance.web   # the NEW address (no destroy/create)
}

# Refactor: resource intentionally dropped — tell TF to forget it, not delete it
removed "aws_instance.old" {               # a removed block for this resource
  from_state = true     # remove from state only, leave the cloud resource
}
```

These are **the** tool for safe refactors that otherwise cause destroy/create churn.

## 7.11 Checks & `terraform test` (1.6+)

**Checks** — assertions on deployed resources:
```hcl
check "web_instance_healthy" {             # a check named "web_instance_healthy"
  for_each = aws_instance.web              # run the check for each web instance

  assert {                                 # one assertion
    condition     = each.value.public_ip != ""   # the instance has a public IP
    failure_message = "Instance ${each.key} has no public IP."
  }
}
# mark resource checkable
resource "aws_instance" "web" {            # the resource under test
  ...
  checkable = true     # (or: checks { id = "web_instance_healthy" })
}
```

**`terraform test`** — unit tests in `.tftest.hcl` files:
```hcl
run "two_instances" {                      # a test named "two_instances"
  variables = { instance_count = 2 }       # set the input variable for this test
  assert {                                 # an assertion
    condition     = length(aws_instance.web) == 2   # exactly 2 instances
    error_message = "Expected 2 instances, got ${length(aws_instance.web)}"
  }
  plan = true          # test the plan (default), or apply = true for live
}
```
`terraform test` runs in an isolated state — safe in CI. (Status: public preview at 1.6; check current release notes for GA.)

## 7.12 Sensitive Values End-to-End

```hcl
variable "db_password" { type = string; sensitive = true }   # a sensitive input

output "db_endpoint" {                 # a NON-sensitive output
  value     = aws_db_instance.main.address   # the DB endpoint
  sensitive = false
}
# NEVER: output "db_password" { value = var.db_password }
```

- `sensitive` masks **display only**. The value is still in state (plaintext JSON).
- In modules, mark the *input* sensitive; it propagates to any output derived from it.
- Real secret management: **data source from a secrets manager** (AWS Secrets Manager, Azure Key Vault), or inject at runtime — don't store in state.

## 7.13 `-replace` and Targeted Changes

```bash
terraform apply -replace=aws_instance.web[0]        # force replace one specific instance
terraform apply -replace=aws_instance.web            # replace all in that collection
terraform plan -replace=aws_instance.web[0] -out=p.tf   # plan the replacement, save to file
```
Use when a resource is **corrupt** or you need a **controlled recreation** (e.g. move an instance to a new AZ).

## 7.14 Ordering, Refresh, and the Plan Output

- Plan lists resources in **topological order** but groups by action.
- `-detailed-exitcode` → exit 2 when changes exist (CI gate).
- `-json` output → machine-readable (used by Infracost, Sentinel, custom tooling).
- `terraform show -json` → inspect state/plan as JSON.

## 7.15 Putting It Together (a "senior" resource)

```hcl
resource "aws_db_instance" "primary" {   # the primary DB instance
  identifier        = "${local.name_prefix}-db"   # a unique identifier
  engine            = "postgres"                   # the engine
  instance_class    = local.env.sizes.db           # size from the env local
  allocated_storage = 100                          # 100 GB
  storage_encrypted = true                         # encrypt the storage
  multi_az          = (var.environment == "prod")  # HA only in prod
  skip_final_snapshot = (var.environment != "prod")  # skip snapshot except prod

  lifecycle {                                   # lifecycle meta-argument
    prevent_destroy        = (var.environment == "prod")   # protect prod
    ignore_changes         = ["auto_minor_version_upgrade"]  # AWS manages this
    create_before_destroy  = true                          # zero-downtime replace
  }

  precondition {                                # fail fast
    condition     = var.environment != "prod" || var.approval_token != ""  # prod needs a token
    error_message = "Prod DB changes require approval_token."
  }
}
```
