# ============================================================================
#  Key Vault — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

data "azurerm_client_config" "current" {}        # the current Azure AD identity

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-kv"                         # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_key_vault" "lab" {             # the Key Vault
  name                = "kv-lab"                # the vault's name (globally unique)
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  tenant_id           = data.azurerm_client_config.current.tenant_id   # the tenant
  sku_name            = "standard"              # the SKU (standard)

  rbac_authorization_enabled = true             # use RBAC (the v5 way) for access control

  # (In v5, RBAC replaces the old "access policy" model — grant a role, not a policy.)
}

resource "azurerm_key_vault_secret" "app" {      # the secret
  name                = "app-secret"            # the secret's name
  key_vault_id        = azurerm_key_vault.lab.id   # which vault
  value               = "SuperSecret-123"       # the secret's value (CHANGE)
}

resource "azurerm_user_assigned_identity" "app" {   # the identity (for an app to use)
  name                = "id-kv-app"             # the identity's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
}

resource "azurerm_role_assignment" "secrets_officer" {   # the grant: the identity can manage secrets
  scope                = azurerm_key_vault.lab.id   # on the vault
  role_definition_name = "Key Vault Secrets Officer"   # the role (full secret access)
  principal_id         = azurerm_user_assigned_identity.app.principal_id   # the identity
}
