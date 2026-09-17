terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.0" }   # Azure provider, any 5.x
  }
}

provider "azurerm" {                             # configure the Azure provider
  features {}                                    # required in v5
}

resource "azurerm_resource_group" "kv" {         # the resource group
  name     = "${var.project}-kv-rg"              # e.g. kvl-kv-rg
  location = var.location                        # from the input
}

data "azurerm_client_config" "current" {         # data block: read "who am I?" (the az login identity)
  # returns object_id, tenant_id, subscription_id of the CURRENT logged-in user
}

resource "azurerm_key_vault" "vault" {           # the Key Vault itself
  name                = "${var.project}kv${var.environment}"   # e.g. kvlkvdev (no hyphens allowed in vault names!)
  location            = var.location            # same location
  resource_group_name = azurerm_resource_group.kv.name   # which group
  tenant_id           = data.azurerm_client_config.current.tenant_id   # your Azure AD tenant
  sku_name            = "standard"              # the SKU (standard or premium)
  rbac_authorization_enabled = false             # required in v5: false = classic access-policy auth (what we use)
}

resource "azurerm_key_vault_access_policy" "me" {   # "who may use the vault": grant YOURSELF access
  key_vault_id = azurerm_key_vault.vault.id     # which vault
  tenant_id    = data.azurerm_client_config.current.tenant_id   # your tenant
  object_id    = data.azurerm_client_config.current.object_id   # YOUR user/service principal

  secret_permissions = ["Get", "Set", "List"]   # what you may do with secrets
}

resource "azurerm_key_vault_secret" "app_secret" {   # the secret itself
  name         = "app-secret"                      # the secret's name
  value        = var.secret_value                  # the value (from the sensitive variable)
  key_vault_id = azurerm_key_vault.vault.id        # which vault

  # Key Vault auto-versions: changing `value` creates a NEW version, the name stays
}

# ── the web app: proof of "serverless" hosting ────────────────────────────────

resource "azurerm_service_plan" "app" {          # the App Service plan: the compute pool
  name                = "${var.project}-f1"      # the plan's name
  location            = var.location            # same location
  resource_group_name = azurerm_resource_group.kv.name   # which group
  os_type             = "Linux"                 # the app runs on Linux
  sku_name            = "F1"                    # F1 = the FREE plan (1 MB RAM, 60 min CPU/day)
}

resource "azurerm_linux_web_app" "app" {         # the web app itself
  name                       = "${var.project}-web"   # the app's name (becomes the URL)
  location                   = var.location          # same location
  resource_group_name        = azurerm_resource_group.kv.name   # which group
  service_plan_id            = azurerm_service_plan.app.id      # which compute pool
  https_only                 = true                  # force HTTPS

  # app_settings is a TOP-LEVEL map in this azurerm version (not inside site_config)
  app_settings = {                                    # environment variables for the app
    "VaultUri" = azurerm_key_vault.vault.vault_uri     # the app can now find the vault
  }

  site_config {}                                      # at least one (empty) site_config block is required
}
