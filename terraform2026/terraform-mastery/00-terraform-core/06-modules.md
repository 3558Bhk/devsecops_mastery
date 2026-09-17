# 6. Modules

> **⏱️ Time to complete: ~45 min** (read + refactor an example into a child module)

## 6.1 What & Why

A **module** = a directory of `.tf` files that encapsulates a reusable unit (a VPC, a serverless API, an entire app). Modules give you:

- **Reuse** (DRY across projects).
- **Encapsulation** (expose only inputs/outputs; hide complexity).
- **Independent versioning** (registry modules with semver).
- **Team boundaries** (each team owns a module; one root module composes them).

**Module anatomy:**

```
modules/vpc/
├── variables.tf      # inputs (typed, described, validated)
├── outputs.tf        # the public contract
├── main.tf           # resources
├── locals.tf
└── (no backend.tf! child modules never declare backends)
```

Rules:
- Child modules **cannot** define `terraform { backend ... }` or `required_providers` *versions* (they CAN declare `required_providers` sources since 1.x, but the *root* resolves).
- Child modules **cannot** define `provider` blocks for *inherited* config — provider config flows down from the root. (A child may define its own provider block if the root hasn't, e.g. for a *different* service.)
- **No nested backend, no `terraform` block with `backend`** in children — that's the root's job.

## 6.2 Using a Module

```hcl
module "vpc" {                         # invoke a child module named "vpc"
  source = "./modules/vpc"             # local path to the module directory

  name            = "prod-vpc"          # input: the VPC display name
  cidr            = "10.40.0.0/16"      # input: the VPC CIDR
  azs             = ["ap-south-1a", "ap-south-1b"]   # input: availability zones
  public_subnet_count = 2               # input: number of public subnets
  private_subnet_count = 2              # input: number of private subnets
}

# consume the module's outputs
output "vpc_id" {                       # an output named "vpc_id"
  value = module.vpc.vpc_id             # value = the vpc_id output of the vpc module
}

# pass outputs to another module
module "compute" {                      # invoke another child module
  source      = "./modules/compute"     # local path
  subnet_ids  = module.vpc.private_subnet_ids   # wire the vpc module's subnets in
  vpc_id      = module.vpc.vpc_id       # wire the vpc module's vpc id in
}
```

### Module sources

| Source | Example |
|---|---|
| Local path | `source = "./modules/vpc"` or `../modules/vpc` |
| Git | `source = "git::https://github.com/acme/terraform-modules.git//modules/vpc?ref=v1.4.0"` |
| Registry | `source = "terraform-aws-modules/vpc/aws"`, `version = "~> 5.0"` |
| HTTPS zip | `source = "https://example.com/modules/vpc.zip"` |
| S3 | `source = "s3::https://bucket.s3.amazonaws.com/vpc.zip?version=1.2.0"` |

Registry address grammar: `<namespace>/<name>/<target>` (target = cloud, e.g. `aws`, `azurerm`, `kubernetes`).

### Module `for_each` (multi-env from one root)

```hcl
module "web" {                          # invoke the web module...
  source = "./modules/web"              # local path
  for_each = var.environments            # ...once PER environment (map key = env name)

  environment = each.key                 # input: the env name (dev/prod)
  config      = each.value               # input: the per-env config object
}
```

> `for_each` on modules: keys are **stable** (from the map), so resources get consistent addresses (`module.web["dev"].aws_instance.app`). Renaming a map key = destroy+create — use `moved` blocks to rename safely.

## 6.3 Module Inputs/Outputs (the contract)

```hcl
# modules/vpc/variables.tf
variable "name" {                        # input: the VPC name
  type        = string                   # must be a string
  description = "VPC display name / tag" # shown in docs
}

variable "cidr" {                        # input: the VPC CIDR
  type    = string                       # must be a string
  default = "10.40.0.0/16"               # default CIDR
  validation {                           # validate it's a real CIDR
    condition     = can(cidrhost(var.cidr, 0))   # true if cidrhost() doesn't error
    error_message = "Must be a valid CIDR block."
  }
}

variable "azs" {                         # input: list of availability zones
  type    = list(string)                 # list of strings
  default = []                           # empty by default
}

variable "extra_tags" {                  # input: additional tags
  type    = map(string)                  # map of strings
  default = {}                           # none by default
}
```

```hcl
# modules/vpc/outputs.tf
output "vpc_id" {                        # output: the VPC id
  value = aws_vpc.main.id                # value = the VPC's id
}

output "private_subnet_ids" {            # output: list of private subnet ids
  value = aws_subnet.private[*].id       # attribute splat over all private subnets
}

output "vpc_endpoint_security_group_id" {  # output: the VPCE security group id
  value = aws_security_group.vpce.id     # the security group's id
}
```

**Contract rules:**
- Export **IDs** (not full objects) unless the consumer truly needs more.
- Sensitive inputs → mark sensitive; sensitive outputs → mark sensitive.
- Add `description` to every variable (it renders in Terraform Cloud docs).
- A module's outputs are its **API surface** — treat breaking changes to them as breaking changes to a library.

## 6.4 Provider Configuration into Modules

- The root's provider config **automatically applies** to child modules (0.13+).
- To force a specific (aliased) provider in a child: pass `providers = { aws = aws.network }`:

```hcl
module "shared_storage" {                # invoke the storage module
  source    = "./modules/storage"        # local path
  providers = {                          # pass explicit provider configurations
    aws = aws.network                     # use the network-account (aliased) provider
  }
  bucket = "shared"                      # input: the bucket name
}
```

- A child module *can* define a provider block for a provider the root did NOT configure (e.g. root uses aws, child also needs `random`).

## 6.5 Module Versioning (registry)

- Tag git releases semver: `v1.0.0`, `v1.1.0`, `v2.0.0`.
- Consumers pin: `version = "~> 1.2"` (allows 1.3, not 2.0).
- Breaking changes (removing inputs/outputs, changing types) → major bump.
- **Module source detection:** registry modules are identified by `<org>/<name>/<target>`; org = your GitHub/Terraform Cloud org.

## 6.6 Module Structure Best Practices

1. **Single responsibility.** One module = one concept (`vpc`, `rds-postgres`, `lambda-api`). A "kitchen sink" module that takes 40 variables is a smell.
2. **Name things inside the module** by role, not environment (`aws_vpc.main`, not `aws_vpc.prod`) — the environment is the *caller's* concern.
3. **Expose the minimum.** If 95% of callers only need `vpc_id` and `subnet_ids`, export those.
4. **Default to safe values** for dev (`force_destroy = false` default, but allow override).
5. **Tag everything** via `default_tags` (provider) or a `common_tags` local + `tags_all` on each resource.
6. **Document:** a `README.md` per module with example usage; consider `terraform-docs` for auto-generated input/output tables.
7. **Test:** small root module with `terraform test` (1.6+) or a CI pipeline that plans against a scratch environment.
8. **Version** with semver from day one; add `CHANGELOG.md`.

## 6.7 Module Dependency Graph

- Modules are nodes; **references between modules** (`module.a.x` used in `module.b`) create edges.
- `terraform graph` shows them (with `-type=module` for a module-only view).
- Cycles between modules are impossible to plan — break with a **data source**, a **dependency on a shared parent**, or by re-scoping.

## 6.8 Module vs Data Source vs Provider Alias — Decision Table

| Need | Tool |
|---|---|
| Reusable, parameterized stack of resources | **Module** |
| Read an existing cloud value (AMI id, current account, DNS zone) | **Data source** |
| Same module, different account/region/subscription | **Provider alias** |
| Same module, different env (dev/prod) | **Separate root module** (or module `for_each`) |

## 6.9 Publishing a Module to Terraform Cloud

1. GitHub repo under your org, e.g. `org/terraform-aws-modules` (or a `modules/` subfolder per module with `versions.tf`).
2. Tag releases (`v1.2.0`).
3. In Terraform Cloud: Settings → Module Registry → add → point at repo/folder.
4. Consumers use `source = "org/vpc/aws"` + `version`.

## 6.10 Common Module Mistakes

| Mistake | Consequence / Fix |
|---|---|
| `count` inside a module driven by `for_each` outside (or vice versa) | Keying surprises; prefer one mechanism per module boundary. |
| Exporting a whole resource object (`value = aws_instance.x`) | Consumer over-couples; export specific attributes. |
| `provider` block in a child module overriding the root silently | Confusing auth/region; pass `providers = {}` from root instead. |
| `var` used in a module before its default is set → interactive prompt in CI | Give every variable a default (or fail in `validation`). |
| Module used with `for_each` + `depends_on` referencing a single instance | Address ambiguity; use `module.x["key"].res`. |
| Forgetting `depends_on` between modules that share an implicit resource | Use explicit `depends_on` on the module or a shared data source. |

## 6.11 The "Modules First" Architecture (how big teams do it)

```
org/
├── modules/
│   ├── vpc/            (versioned, tested, published)
│   ├── compute/
│   ├── database/
│   └── networking/
└── environments/
    ├── dev/
    │   ├── main.tf     # composes modules
    │   ├── variables.tf
    │   ├── backend.tf  # s3 key = "dev/global.tfstate"
    │   └── terraform.tfvars
    ├── staging/
    └── prod/
```

- `modules/` = **library** (stable, versioned, CI-tested).
- `environments/` = **composition** (thin: pass variables, wire modules).
- Each environment dir = **one state**. This is the pattern you'll see in every serious Terraform codebase.
