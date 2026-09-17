# Azure 2 — Azure Foundations, Identity & Key Vault

> **⏱️ Time to complete: ~50 min** (read + create an RG + a Key Vault secret)

## 2.1 The Azure Hierarchy

```
Management Group(s)
   └── Subscription  (billing + access boundary; you authenticate to a subscription)
         └── Resource Group  (a container; resources live in exactly one RG)
               └── Resource  (VM, VNet, Storage, SQL, ...)
```

- **Subscription** = the thing you authenticate to + the billing boundary. One tenant can have many.
- **Resource Group (RG)** = a **logical container**. Resources are **1:1 with an RG**. You **cannot** move a resource between RGs in place (you must recreate, or use `az resource move`).
- **Location (region)** = each resource has one (e.g. `eastus`, `australiacentral`, `westeurope`).
- **Resource providers** = per-service APIs (e.g. `Microsoft.Compute`). Some must be **registered** in a region before you can use them (v5: not auto by default).

> **RG vs Region**: an RG is **region-scoped** (has a location), but the resources inside can be in **different regions** (though most are in the RG's region).

## 2.2 Naming Constraints (know the big ones)

| Resource | Constraint |
|---|---|
| **Storage account** | 3–24 **lowercase letters/digits**, **globally unique** (all of Azure) → use `uuidv5` or a prefix. |
| **Resource group** | 1–90 chars, letters/digits/`_`/`-`/`.`, must end with a letter or number. |
| **Virtual network** | 1–64 chars. |
| **VM** | 1–64, letters/digits/`-`. |
| **Key Vault** | 3–24 **lowercase letters/digits**, **globally unique**, no hyphens. |
| **SQL server** | 1–63, **globally unique** (lowercase, digits, `-`). |

Use `uuidv5("https://example.com/salt", "name")` or `replace()` to generate stable, compliant, unique names.

## 2.3 Resource Group (the starting point of every stack)

```hcl
data "azurerm_client_config" "current" {}   # read the current identity (tenant/sub)

resource "azurerm_resource_group" "main" {   # create the resource group
  name     = var.rg_name                     # the RG name
  location = var.location                    # the location (region)
  tags     = local.common_tags               # the common tags
}
```

## 2.4 Useful Data Sources

```hcl
data "azurerm_client_config" "current" {   # the current identity
  # client_id, tenant_id, subscription_id
}

data "azurerm_subscription" "current" {    # the current subscription's details
  # (resolves the current subscription)
}

data "azurerm_resource_group" "existing" {   # read an EXISTING resource group
  name = var.rg_name      # the RG name
}

data "azurerm_client_config" "c" {          # (another alias for the identity)
  # for SP principal_id (for role assignments)
}
```

## 2.5 Entra ID (formerly Azure AD) — the Identity Layer

**Key objects:**
- **Tenant** = your organization's directory (one per org).
- **User** = a person (or a **service principal** = an app).
- **App Registration** = an application's identity (has a **client_id** / object id).
- **Service Principal** = the *tenant-specific* instance of an app registration (what you actually assign roles to).
- **Role** (RBAC) = a set of permissions (Owner, Contributor, Reader, or custom).
- **Role Assignment** = grants a Role to a principal (user/SP/group) at a **scope** (mgmt group / subscription / RG / resource).

**RBAC roles you'll use:**
- **Owner** = full control + manage access (broad; avoid for CI).
- **Contributor** = manage resources, **not** access (the CI default).
- **User Access Administrator** = manage RBAC (grant roles) — needed to create role assignments.
- **Reader** = read-only.

> **Important:** to **create a role assignment** (e.g. for a managed identity or SP), the principal running Terraform needs **User Access Administrator** (or Owner) at that scope. Contributor alone **cannot** grant roles.

### Managing an App Registration + SP + Role in Terraform

```hcl
# (Requires the `azurerm` provider + `hashicorp`/`azuread` provider for full Entra objects;
#  the azurerm provider covers the SP role-assignment side via azurerm_role_assignment.)

resource "azurerm_role_assignment" "tf_sp" {   # a role assignment
  scope                = data.azurerm_resource_group.main.id   # the scope (the RG)
  role_definition_name = "Contributor"          # the role
  principal_id         = var.sp_object_id      # the service principal's object id
}
```

For full app-registration management, use the **`hashicorp/azuread`** provider (separate from `azurerm`):
```hcl
terraform {                          # the terraform block
  required_providers {               # declare providers
    azuread = { source = "hashicorp/azuread"; version = "~> 3.0" }   # the azuread provider
  }
}

resource "azuread_application" "tf" {              # an application registration
  display_name = "tf-automation"                   # the app name
}

resource "azuread_service_principal" "tf" {        # the service principal for the app
  application_id = azuread_application.tf.application_id   # the app's id
}

resource "azuread_federated_identity_credential" "gha" {   # an OIDC federated credential
  display_name            = "github"                 # a friendly name
  service_principal_id    = azuread_service_principal.tf.id   # the SP
  issuer                  = "https://token.actions.githubusercontent.com"   # the GHA issuer
  subject                 = "repo:myorg/infra:ref:refs/heads/main"   # only this repo+branch
  description             = "GHA OIDC"               # description
}
```

## 2.6 Managed Identity (the preferred, keyless identity for Azure resources)

Two kinds:
- **System-assigned** = created with the resource, lives/dies with it.
- **User-assigned** = standalone, can be shared by many resources.

```hcl
# User-assigned identity
resource "azurerm_user_assigned_identity" "app" {   # a user-assigned identity
  name                = "${local.name_prefix}-app-identity"   # the name
  resource_group_name = azurerm_resource_group.main.name   # the RG
  location            = azurerm_resource_group.main.location   # the location
}

# Grant it a role (e.g. read a Key Vault secret)
resource "azurerm_role_assignment" "kv" {           # a role assignment
  scope                = azurerm_key_vault.kv.id    # the scope (the Key Vault)
  role_definition_name = "Key Vault Secrets User"   # the role
  principal_id         = azurerm_user_assigned_identity.app.principal_id   # the identity
}

# Attach it to a VM
resource "azurerm_linux_virtual_machine" "app" {    # a VM
  ...
  identity {                                # the identity block
    type         = "SystemAssigned"         # a system-assigned identity
    # type = "UserAssigned"
    # identity_ids = [azurerm_user_assigned_identity.app.id]   # (or user-assigned)
  }
}
```

- **`principal_id`** = the identity's object id (used in role assignments).
- **`client_id`** = the app id (used for auth).
- Managed identities = **no secrets to manage** — the VM/Function gets a token automatically. **Prefer over embedded keys/SPs.**

## 2.7 Key Vault (secrets, keys, certs)

```hcl
resource "azurerm_key_vault" "kv" {            # a Key Vault
  name                = "${local.name_prefix}-kv"      # lowercase, no hyphens, globally unique
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  tenant_id           = data.azurerm_client_config.current.tenant_id   # the tenant
  sku_name            = "standard"             # the SKU
  soft_delete_retention_days = 90              # soft-delete retention
  purge_protection_enabled   = (var.environment == "prod")   # purge protection (prod)
  enabled_for_deployment     = true            # allow VM deployments to use it
  enabled_for_disk_encryption = true           # allow disk encryption
  enabled_for_template_deployment = true       # allow template deployments

  tags = local.common_tags                     # the common tags
}

resource "azurerm_key_vault_secret" "db_password" {   # a secret
  name         = "db-password"                   # the secret name
  key_vault_id = azurerm_key_vault.kv.id         # the Key Vault
  value        = random_password.db.result       # the secret value
  content_type = "text/plain"                    # the content type
  tags         = { owner = "platform" }          # tags
}

# Read a secret (consume it)
data "azurerm_key_vault_secret" "db_password" {   # read the secret
  name         = "db-password"                   # the secret name
  key_vault_id = azurerm_key_vault.kv.id         # the Key Vault
}
# use: password = data.azurerm_key_vault_secret.db_password.value
```

### Access control: Access Policies (legacy) vs RBAC (modern)

- **Legacy access policy** (still supported, in the provider):
```hcl
resource "azurerm_key_vault" "kv" {            # the Key Vault
  ...
  access_policy {                               # an access policy (legacy)
    tenant_id = data.azurerm_client_config.current.tenant_id   # the tenant
    object_id = azurerm_user_assigned_identity.app.principal_id   # the identity
    secrets_permissions = ["Get", "List"]        # the permitted secret operations
  }
}
```
- **RBAC (recommended)**: grant a Key Vault role (`Key Vault Secrets User`, `Key Vault Contributor`, etc.) via `azurerm_role_assignment` (above).

> Modern guidance: **RBAC over access policies** (more scalable, consistent with the rest of Azure). The provider still exposes `access_policy` for compatibility.

## 2.8 Getting It Right / Gotchas

- **Storage/KeyVault/SQL names are globally unique** → use `uuidv5` or a strong prefix.
- **Resources are 1:1 with an RG** (can't move in place).
- **Granting roles needs User Access Administrator/Owner** (Contributor can't).
- **Managed identity** = the preferred keyless identity (system vs user-assigned).
- **RBAC over access policies** for Key Vault.
- **v5**: resource providers not auto-registered (register or set `legacy`).
- **`data.azurerm_client_config`** = always know your tenant/subscription.
- Use a **separate RG per environment** (or per service+env).

## 2.9 Interview Quick Facts

- Hierarchy: **Mgmt Group → Subscription → RG → Resource**.
- **RG** = logical container; resources 1:1 with an RG; RG is region-scoped.
- **RBAC roles**: Owner / Contributor / Reader / User Access Administrator.
- **Service principal** = app identity (client_id + object id).
- **Managed identity** = keyless identity for Azure resources (system/user-assigned).
- **Key Vault** = secrets/keys/certs; **RBAC** (modern) over **access policies** (legacy).
- **Globally unique names**: storage account, key vault, SQL server.
- **`data.azurerm_client_config`** = current identity.
