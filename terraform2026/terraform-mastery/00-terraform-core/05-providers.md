# 5. Providers

> **⏱️ Time to complete: ~35 min** (read + configure both AWS & Azure providers)

## 5.1 What a Provider Is

A **provider** is a plugin that knows how to talk to one cloud/API: its resources, data sources, and schemas. Terraform core contains *no* cloud logic.

- Official providers: `hashicorp/aws`, `hashicorp/azurerm`, `hashicorp/google`, `hashicorp/kubernetes`, `hashicorp/null` (local testing), `hashicorp/random` (string/int/password), `hashicorp/http`, `hashicorp/tls`.
- Community: `terraform-aws-modules/*` modules are *not* providers; providers live in the **Registry** under `registry.terraform.io/<namespace>/<type>`.

## 5.2 Declaring Providers

```hcl
terraform {                          # the terraform config block
  required_providers {               # declare the providers this config uses
    aws = {                          # provider label "aws"
      source  = "hashicorp/aws"      # registry address (namespace/type)
      version = "~> 5.0"             # allow any 5.x, never 6.x
    }
    azurerm = {                      # provider label "azurerm"
      source  = "hashicorp/azurerm"  # the Azure provider
      version = "~> 5.0"             # allow any 5.x
    }
    random  = { source = "hashicorp/random" }   # version optional (any version accepted)
  }
}
```

- `terraform init` resolves these, downloads binaries (with checksums), and records them in **`.terraform.lock.hcl`** — commit that file.
- If config references an undeclared provider → error. Good: it forces explicitness.

## 5.3 Provider Configuration Block

```hcl
provider "aws" {                     # configure the default AWS provider
  region  = "ap-south-1"             # target region
  profile = "admin"                  # use the "admin" profile from ~/.aws/credentials
}
```

- One default config per provider in the root (or module). Resources use it implicitly.
- **Provider blocks inside child modules are ignored for inheritance since 0.13** — configuration flows *down* from where it's defined; child modules can add their own but the parent's applies first (see aliases for multi-region).

## 5.4 Aliased Providers (multi-account / multi-region)

The classic pattern for **AWS multi-account**:

```hcl
terraform {                          # terraform config block
  required_providers {               # declare providers
    aws = {                          # the aws provider
      source = "hashicorp/aws"       # registry address
      configuration_aliases = [      # list the aliases you'll define below
        aws.data,                     # alias for the data account
        aws.network,                  # alias for the network account
      ]
    }
  }
}

provider "aws" {                      # DEFAULT provider = workload account
  region = var.region                 # target region
  assume_role {                       # assume this role (switch account)
    role_arn = "arn:aws:iam::111111111111:role/tf-workload"   # the workload-account TF role
  }
}

provider "aws" {                      # ALIASED provider = network account
  alias  = "network"                  # the alias name (referenced as aws.network)
  region = var.region                 # same region
  assume_role {                       # assume the network-account role
    role_arn = "arn:aws:iam::222222222222:role/tf-network"    # network-account TF role
  }
}

provider "aws" {                      # ALIASED provider = data account
  alias  = "data"                     # the alias name (referenced as aws.data)
  region = var.region                 # same region
  assume_role {                       # assume the data-account role
    role_arn = "arn:aws:iam::333333333333:role/tf-data"       # data-account TF role
  }
}
```

Usage — **both** the resource type AND the alias must match:

```hcl
resource "aws_s3_bucket" "shared" {   # an S3 bucket
  provider = aws.network              # explicitly use the network-account provider
  bucket   = "shared-333333333333"    # bucket name (namespaced by account)
}

resource "aws_instance" "web" {       # an EC2 instance
  provider = aws   # or just omit (uses the default provider)
  ...
}
```

Same technique works for:
- **Multiple AWS regions** (same account, different `region` per alias).
- **Azure**: different subscriptions/tenants (`provider "azurerm" { alias = "prod"; subscription_id = "..." }`).
- **Multiple GCP projects**, etc.

## 5.5 Provider-Level Defaults (AWS examples)

```hcl
provider "aws" {                      # the AWS provider config
  region  = var.region                # target region from a variable
  profile = "admin"                   # shared-credentials profile

  default_tags = {                    # auto-applied to every taggable resource
    Environment   = var.environment   #  env tag
    ManagedBy     = "terraform"       #  managed-by tag
    CostCenter    = "1001"            #  cost-allocation tag
    Terraform     = "true"            #  marker tag
  }

  max_retries = 10                    # retry transient 5xx/throttling errors up to 10x

  # For LocalStack / MinIO testing (commented out; never in prod):
  # s3_use_path_style            = true
  # skip_credentials_validation  = true   # DANGEROUS — testing only
  # skip_metadata_api_check      = true
  # skip_region_validation       = true

  # Custom endpoints (LocalStack, sovereign clouds, testing):
  # endpoints {
  #   s3   = "http://localhost:4566"
  #   ec2  = "http://localhost:4566"
  # }
}
```

`default_tags` is the single best provider feature: tag policy enforcement without repeating `tags` everywhere. (Resources can still override individual keys in their own `tags` block.)

## 5.6 Azure Provider: `features {}` Block

The azurerm provider requires a **features** block (v4: nested inside `required_features`; v5: top-level):

```hcl
# azurerm v5.x
provider "azurerm" {                  # the Azure provider config
  subscription_id = var.subscription_id   # which subscription to manage
  tenant_id       = var.tenant_id        # the Entra ID tenant
  client_id       = var.client_id        # the service principal's app id
  client_secret   = var.client_secret    # the service principal's secret

  features {}   # REQUIRED — per-resource-type behavior tuning (defaults shown below)
}
```

What the `features` block tunes (each is optional):

```hcl
features {                           # the features block (behavior tuning)
  key_vault {                        # Key Vault behavior
    purge_protection_enabled = false # allow purge
    recovery_mode            = false # normal recovery mode
    soft_delete_retention_days = 90  # soft-delete retention
  }
  managed_identity {                 # managed identity behavior
    send_identity_id = false         # don't send identity id
  }
  netapp {                           # NetApp behavior
    enable_ccm_check = false         # disable ccm check
  }
  recovery_service {                 # Recovery Services behavior
    recovery_vault_sync_exception = false   # normal sync
  }
  template_deployment {              # ARM template deployment behavior
    internal_deployer = false        # use the external deployer
  }
}
```

> v5.0 change: **resource providers are NOT auto-registered by default** (`resource_provider_registrations = "none"`). If you relied on v4's auto-registration behavior, set `resource_provider_registrations = "legacy"` in the provider block (or register providers out-of-band).

## 5.7 Data Sources & Provider Auth Basics

- A provider exposes **resources** (Terraform creates/manages) and **data sources** (read-only lookups: `data "aws_ami"`, `data "azurerm_client_config"`).
- Auth is *per provider* (AWS: env/profile/assume-role; Azure: SP/MSI/OIDC) — see the cloud-specific chapters.
- A provider config is **evaluated per resource**; two resources in the same module can use different aliases → different accounts/regions.

## 5.8 `dev_overrides` (provider developers)

```hcl
terraform {                          # terraform config block
  dev_overrides {                    # bypass registry download for a provider under development
    "hashicorp/aws" = "/home/me/src/github.com/hashicorp/terraform-provider-aws"  # local build path
  }
}
```

Bypasses registry download; used when building/forking a provider. `terraform init` will warn but works offline.

## 5.9 Private Provider Registry (enterprises)

- Air-gapped or compliance-restricted orgs run a **filesystem mirror** (see `~/.terraformrc` in ch.1) or a full **private registry** (Terraform Cloud offers one; open-source: `terraform-bcr`-style mirrors).
- `provider_installation` in CLI config controls resolution order (mirror first, direct second).

## 5.10 Provider Upgrade Discipline

1. Pin with `~> X.0` → new minor/patch within major.
2. When a **major** arrives (aws 5→6, azurerm 5→6):
   - Read the release notes for **removed arguments** (they do happen).
   - Upgrade in a **dev environment** first; run `terraform plan` and read every diff.
   - Update `.terraform.lock.hcl` via `terraform init -upgrade`.
3. Keep **provider version = part of your code review**, not an afterthought.

## 5.11 Common Provider Errors

| Error | Meaning / Fix |
|---|---|
| `Error: Invalid provider configuration` | Bad provider arg (typo, region name). Fix the `provider` block. |
| `NoCredentialProviders` | AWS auth missing (see AWS 01). |
| `Error: Missing subscription id` | azurerm: set `subscription_id` or use `az account set`. |
| `The client ... is not authorized to execute ...` | RBAC/IAM role missing a permission → grant it. |
| Provider version conflict | Two modules require different majors → align constraints or use aliases. |
| `Plugin re-execution` warning | Two provider versions in one run (lock file drift) → `init -upgrade`. |

## 5.12 Interview Quick Facts

- Provider = plugin = one API; Terraform core is provider-agnostic.
- Aliases let **one config** span accounts/regions/subscriptions.
- The **lock file** pins provider binaries by hash → reproducible builds.
- `default_tags` (AWS) = the tag-policy layer at the provider.
- azurerm's `features {}` block exists because some Azure resources need *behavior tuning* per environment (soft-delete retention, deploy mode, etc.).
- Providers have **stateless** sessions — everything important is in *your* state, not the provider's memory.
