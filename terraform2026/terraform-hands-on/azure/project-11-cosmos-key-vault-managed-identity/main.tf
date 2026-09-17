terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 5.0" }   # Azure provider, any 5.x
  }
}

provider "azurerm" {                             # configure the Azure provider
  features {}                                    # required in v5
}

data "azurerm_client_config" "current" {         # data block: who am I (the az login identity)
  # returns object_id / tenant_id of the current user
}

resource "azurerm_resource_group" "app" {        # the resource group
  name     = "${var.project}-app-rg"             # e.g. cosmos-app-rg
  location = var.location                        # from the input
}

# ── the NoSQL store: Cosmos DB (SQL API) ──────────────────────────────────────

resource "azurerm_cosmosdb_account" "orders" {   # the Cosmos account
  name                = "${var.project}-cosmos-2026"   # globally unique, lowercase
  location            = var.location              # the region (top-level attr, required in this provider version)
  resource_group_name = azurerm_resource_group.app.name   # which group
  offer_type          = "Standard"                # the pricing/SLA offer
  kind                = "GlobalDocumentDB"        # the SQL API (a.k.a. DocumentDB)

  consistency_policy {                              # how consistent reads are (block, required)
    consistency_level = "Session"                   # per-session consistency (the sweet spot for most apps)
  }

  geo_location {                                    # the region (this provider version needs a geo_location block)
    location          = var.location               # which region
    failover_priority = 0                          # 0 = primary (no failover partner in the lab)
  }
}

resource "azurerm_cosmosdb_sql_database" "appdb" {   # the database inside the account
  name           = "appdb"                            # the database's name
  account_name   = azurerm_cosmosdb_account.orders.name   # which account (by name in this provider version)
  resource_group_name = azurerm_resource_group.app.name   # which group (required)
  throughput     = 400                                # 400 RU/s (the minimum; database-level = shared; fixed, not autoscale)
}

resource "azurerm_cosmosdb_sql_container" "orders" {   # the container (a "table")
  name           = "orders"                            # the container's name
  account_name   = azurerm_cosmosdb_account.orders.name   # which account (by name)
  resource_group_name = azurerm_resource_group.app.name   # which group (required)
  database_name  = azurerm_cosmosdb_sql_database.appdb.name   # which database
  partition_key_kind = "Hash"                           # the partitioning scheme
  partition_key_paths = ["/id"]                         # the partition key path (how data is sharded)
  throughput     = null                               # null = use the database-level 400 RU (cheaper)
}

# ── the secret store: Key Vault ───────────────────────────────────────────────

resource "azurerm_key_vault" "secrets" {          # the Key Vault
  name                = "${var.project}-vault"    # e.g. cosmos-vault (max 24 chars, no leading digit)
  location            = var.location              # same location
  resource_group_name = azurerm_resource_group.app.name   # which group
  tenant_id           = data.azurerm_client_config.current.tenant_id   # your tenant
  sku_name            = "standard"                # the SKU
  rbac_authorization_enabled = false               # required in v5: classic access-policy auth
}

resource "azurerm_key_vault_secret" "db_password" {   # the secret: the DB password
  name         = "db-password"                       # the secret's name
  value        = var.db_password                     # the value (from the sensitive variable)
  key_vault_id = azurerm_key_vault.secrets.id        # which vault
}

# ── the app: a web app with a managed identity (NO client secrets) ────────────

resource "azurerm_service_plan" "app" {           # the compute pool (F1 = free)
  name                = "${var.project}-f1"       # the plan's name
  location            = var.location             # same location
  resource_group_name = azurerm_resource_group.app.name   # which group
  os_type             = "Linux"                  # Linux plan
  sku_name            = "F1"                     # FREE plan
}

resource "azurerm_linux_web_app" "app" {          # the web app
  name                       = "${var.project}-vault-web"   # the app's name
  location                   = var.location            # same location
  resource_group_name        = azurerm_resource_group.app.name   # which group
  service_plan_id            = azurerm_service_plan.app.id      # the free pool
  https_only                 = true                   # force HTTPS

  identity { type = "SystemAssigned" }               # the app gets an Azure AD IDENTITY (the key to everything)

  # app_settings is a TOP-LEVEL map in this azurerm version
  app_settings = {                                       # the app's configuration
    "CosmosEndpoint" = azurerm_cosmosdb_account.orders.endpoint   # where the DB is
  }

  site_config {}                                       # an empty site_config block is required

  # The secret is referenced from the vault BY NAME — the value never enters this config
  # (the app's identity above is what's allowed to read it — see the access policy below)
}

# The access policy: allow the APP'S IDENTITY (and you) to read the secret
# NOTE: the web app's principal_id is computed when the app is created, so the
# policy is attached AFTER the app exists (Terraform orders this via the reference).
resource "azurerm_key_vault_access_policy" "app_identity" {   # the app's identity may read the secret
  key_vault_id = azurerm_key_vault.secrets.id     # which vault
  tenant_id    = azurerm_linux_web_app.app.identity[0].tenant_id   # the tenant (from the app's identity)
  object_id    = azurerm_linux_web_app.app.identity[0].principal_id   # THE app's principal id

  secret_permissions = ["Get"]              # read-only: the app can fetch the secret, not change it
}

resource "azurerm_key_vault_access_policy" "me" {   # and you (the az login user) may read it too (for verifying)
  key_vault_id = azurerm_key_vault.secrets.id     # which vault
  tenant_id    = data.azurerm_client_config.current.tenant_id   # your tenant
  object_id    = data.azurerm_client_config.current.object_id   # your user

  secret_permissions = ["Get", "List"]     # read + list (so `az keyvault secret show` works)
}
