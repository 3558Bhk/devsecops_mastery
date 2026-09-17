# Azure 1 — Provider Setup & Authentication

> **⏱️ Time to complete: ~45 min** (read + verify auth with `data.azurerm_client_config`)

## 1.1 The Provider Block (azurerm v5.x — current)

```hcl
terraform {                          # the terraform config block
  required_providers {               # declare required providers
    azurerm = {                      # the Azure provider
      source  = "hashicorp/azurerm"  # registry address
      version = "~> 5.0"             # any 5.x, never 6.x
    }
  }
}

provider "azurerm" {                  # configure the Azure provider
  # Auth (one of the methods below)
  client_id       = var.client_id     # the service principal's app id
  client_secret   = var.client_secret # the service principal's secret
  tenant_id       = var.tenant_id     # the Entra ID tenant
  subscription_id = var.subscription_id   # the target subscription

  features {}   # REQUIRED in v4/v5 — behavior tuning per resource type
}
```

> **v4 vs v5:** In azurerm **v4** the block was `required_features { features {} }` (nested). In **v5** it's the top-level `features {}` shown above. Both mean the same thing. If you see older tutorials with `required_features`, they're v4.
>
> **v5 breaking note:** In v5, **resource providers are NOT auto-registered by default** (`resource_provider_registrations = "none"`). v4 auto-registered them. If you depended on that, set `resource_provider_registrations = "legacy"` in the provider (or register providers out-of-band).

## 1.2 The `features {}` Block (required, per-resource tuning)

```hcl
features {                           # the features block (required)
  key_vault {                        # Key Vault behavior tuning
    purge_protection_enabled   = false   # allow purge
    soft_delete_retention_days = 90      # soft-delete retention (days)
  }
  managed_identity {                 # managed identity tuning
    send_identity_id = false           # don't send the identity id
  }
  netapp {                           # NetApp tuning
    enable_ccm_check = false           # disable the ccm check
  }
  neptune {                          # Neptune tuning
    disable_cni_network_monitor = false   # don't disable the CNI network monitor
  }
  recovery_service {                 # Recovery Services tuning
    recovery_vault_sync_exception = false   # normal sync
  }
  template_deployment {              # ARM template deployment tuning
    internal_deployer = false          # use the external deployer
  }
}
```

Most teams just write `features {}` (all defaults) and only tune when a specific resource demands it (e.g. key vault retention).

## 1.3 Authentication Methods (pick one)

### A) Service Principal with client secret (most common for CI + dev)

```hcl
provider "azurerm" {                  # the provider block
  client_id       = var.client_id     # the SP's app id
  client_secret   = var.client_secret # the SP's secret
  tenant_id       = var.tenant_id     # the tenant
  subscription_id = var.subscription_id   # the subscription
}
```

Create the SP (via az CLI):
```bash
az ad sp create-for-rbac --name tf-sp --role Contributor \
  --scopes /subscriptions/<SUB_ID> \
  --sdk-auth > tf-azure-auth.json     # gives client_id, client_secret, tenant_id, subscription_id
```
Or manage it **in Terraform** (see ch. 2 — app registration + role assignment).

### B) Service Principal with client **certificate** (no secret to rotate)

```hcl
provider "azurerm" {                  # the provider block
  client_id       = var.client_id     # the SP's app id
  tenant_id       = var.tenant_id     # the tenant
  subscription_id = var.subscription_id   # the subscription

  client_certificate = base64encode(file("client.crt"))   # the cert (or a password-protected PFX)
  # client_certificate_password = "..."   # (if the PFX is password-protected)
}
```

### C) **OIDC** (GitHub Actions — the modern CI pattern, no secrets at all)

```hcl
provider "azurerm" {                  # the provider block
  # No client_secret! The provider reads the federated token from env:
  #   AZURE_FEDERATED_TOKEN_FILE (set by the azure/login action)
  #   AZURE_CLIENT_ID, AZURE_TENANT_ID
  subscription_id = var.subscription_id   # the subscription
}
```

GitHub Actions:
```yaml
- uses: azure/login@v2               # the Azure OIDC login action
  with:
    client-id: ${{ vars.AZURE_CLIENT_ID }}         # the SP's app id
    tenant-id: ${{ vars.AZURE_TENANT_ID }}         # the tenant
    subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}   # the subscription
```

The app registration needs a **federated credential** (OIDC issuer `https://token.actions.githubusercontent.com`, subject `repo:org/repo:ref:refs/heads/main`).

### D) **Managed Identity** (when Terraform itself runs in Azure — e.g. an Azure DevOps self-hosted agent, or a VM)

```hcl
provider "azurerm" {                  # the provider block
  use_msi         = true              # use the managed identity for auth
  subscription_id = var.subscription_id   # the subscription
  # client_id       = (optional; a specific user-assigned identity)
  # tenant_id       = (optional)
}
```

### E) **Azure CLI login** (legacy convenience; `azure_cli` feature)

```hcl
provider "azurerm" {                  # the provider block
  features {                           # the features block
    # (azure_cli auth is implicit when no other auth is configured and `az login` was run)
  }
}
```
Run `az login` (interactive) first. Not recommended for CI (interactive, session-based) but handy for quick local experiments.

### F) **Device login** (local, interactive, no SP)

```hcl
provider "azurerm" {                  # the provider block
  subscription_id = var.subscription_id   # the subscription
}
# features {
#   aad_device_login = { ... }   # provider prompts a browser device-code login
# }
```

## 1.4 Useful Provider Arguments

| Argument | Purpose |
|---|---|
| `client_id` / `client_secret` / `client_certificate` | Service principal auth |
| `tenant_id` | Entra ID tenant |
| `subscription_id` | Target subscription |
| `use_msi` | Managed identity auth |
| `environment` | `public` (default), `USGov`, `China` |
| `resource_group_name` | Default RG for resources that need one (optional) |
| `auxiliary_tenant_ids` | Cross-tenant scenarios |
| `client_certificate` / `client_certificate_password` | Cert-based auth |
| `skip_provider_registration` | Skip resource-provider registration (speeds up plan in CI) |
| `resource_provider_registrations` | `legacy` / `none` (v5) |
| `features {}` | Per-resource-type behavior (required) |

## 1.5 Verifying Your Setup

```hcl
data "azurerm_client_config" "current" {   # read the current identity
}

output "whoami" {                            # expose it as an output
  value = {                                  # an object with all the facts
    client_id       = data.azurerm_client_config.current.client_id       # the SP's app id
    tenant_id       = data.azurerm_client_config.current.tenant_id       # the tenant
    subscription_id = data.azurerm_client_config.current.subscription_id # the subscription
  }
}
```

`terraform plan` → the output tells you **exactly which subscription/tenant** you're modifying. Do this first in any new stack.

## 1.6 Multi-Subscription / Multi-Tenant (aliases)

```hcl
terraform {                          # the terraform config block
  required_providers {               # declare providers
    azurerm = {                      # the azurerm provider
      source = "hashicorp/azurerm"   # registry address
      configuration_aliases = [azurerm.prod]   # the aliases you'll define
    }
  }
}

provider "azurerm" {                       # DEFAULT = dev subscription
  client_id       = var.client_id     # the SP's app id
  client_secret   = var.client_secret # the SP's secret
  tenant_id       = var.tenant_id     # the tenant
  subscription_id = var.dev_subscription_id   # the DEV subscription
  features {}                             # the features block
}

provider "azurerm" {                       # ALIASED = prod subscription
  alias             = "prod"            # alias name → referenced as azurerm.prod
  client_id         = var.client_id     # same SP
  client_secret     = var.client_secret # same secret
  tenant_id         = var.tenant_id     # same tenant
  subscription_id   = var.prod_subscription_id   # the PROD subscription
  features {}                             # the features block
}

resource "azurerm_resource_group" "prod" {   # an RG (in the default sub here)
  name     = "rg-prod"                      # the name
  location = "australiacentral"             # the location
}
# (would set provider = azurerm.prod if you want it in the prod subscription)
```

## 1.7 Common Auth Errors

| Error | Cause / Fix |
|---|---|
| `Failed login with ... invalid_client` | Bad `client_id`/`client_secret`. Re-generate the SP. |
| `authentication failed ... subscription` | `subscription_id` wrong, or SP not a member of that subscription. |
| `The client ... is not authorized to execute ...` | SP's **role assignment** missing a permission → grant it (RBAC). |
| `AADSTS... user interaction required` | Device login needed / no SP. |
| `Resource provider not registered` | v5 default is no auto-registration → register the provider or set `legacy`. |
| OIDC: token not found | `azure/login` didn't run / wrong `client-id` (must match the federated credential). |

## 1.8 Getting It Right

- **OIDC** (CI) or **SP with cert** (dev) — avoid long-lived client secrets.
- **Least privilege**: scope the SP's role assignment to a **resource group**, not the whole subscription, where possible.
- **`features {}`** is required — don't forget it (v4/v5).
- **v5**: no auto resource-provider registration by default (`resource_provider_registrations = "none"`).
- **`data.azurerm_client_config`** = always verify which tenant/subscription you're in.
- **`skip_provider_registration = true`** speeds up CI (if providers are already registered).

## 1.9 Interview Quick Facts

- azurerm provider = the Azure RM (Resource Manager) API.
- Auth = **Service Principal** (secret/cert) / **OIDC** / **MSI** / device / CLI.
- **`features {}`** block is required (v4 nested `required_features`, v5 top-level).
- **OIDC** (GHA → federated credential) is the modern CI pattern (no secrets).
- **v5**: no auto resource-provider registration by default.
- `data.azurerm_client_config` = current identity (client/tenant/subscription).
