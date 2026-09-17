# ── SECRETS: the DB password lives in Key Vault, not in the VM or the code ─────

data "azurerm_client_config" "current" {             # data block: read "who am I?" (the az login identity)
  # returns your object_id / tenant_id
}

resource "azurerm_key_vault" "secrets" {             # the Key Vault
  name                = "${var.project}vault"       # e.g. capstvault (no hyphens in vault names, max 24 chars)
  location            = var.location               # same location
  resource_group_name = azurerm_resource_group.capstone.name   # which group
  tenant_id           = data.azurerm_client_config.current.tenant_id   # your tenant
  sku_name            = "standard"                 # the SKU
  rbac_authorization_enabled = false               # required in v5: classic access-policy auth
}

resource "azurerm_key_vault_access_policy" "me" {    # grant YOURSELF read access to the vault
  key_vault_id = azurerm_key_vault.secrets.id       # which vault
  tenant_id    = data.azurerm_client_config.current.tenant_id   # your tenant
  object_id    = data.azurerm_client_config.current.object_id   # your user

  secret_permissions = ["Get", "List"]              # read-only for the lab
}

resource "azurerm_key_vault_secret" "db_password" {  # the secret itself: the DB password
  name         = "db-password"                       # the secret's name
  value        = var.sql_password                    # the value (from the sensitive variable)
  key_vault_id = azurerm_key_vault.secrets.id        # which vault
}
