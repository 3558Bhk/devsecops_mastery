# ============================================================================
#  Capstone 4 — Azure Serverless Order Platform
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

data "azurerm_client_config" "current" {}        # the current caller (for tenant ids)

# ═══════════════════════════════════════════════════════════════════════════════
# CAPSTONE 4 — AZURE SERVERLESS ORDER PLATFORM
# Front Door → App Service → Service Bus (topic) → Functions → Cosmos DB
# + Key Vault (RBAC) for the secrets
# ═══════════════════════════════════════════════════════════════════════════════

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-order"                      # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_service_plan" "app" {          # the plan
  name                = "asp-order"             # the plan's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  os_type             = "Linux"                 # the OS type
  sku_name            = "F1"                    # the SKU (the cheapest dedicated)
}

resource "azurerm_linux_web_app" "api" {         # the order API
  name                = "api-order"             # the app's name (globally unique)
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  service_plan_id     = azurerm_service_plan.app.id   # which plan
  https_only          = true                     # force HTTPS

  site_config {                                   # the site config (required in v5)
    always_on = false                           # no keep-alive
  }

  identity {                                  # the app's identity
    type = "SystemAssigned"                   # a system-assigned identity
  }

  app_settings = {                                # the settings
    "SB_NAMESPACE" = azurerm_servicebus_namespace.lab.name   # the Service Bus namespace
  }
}

resource "azurerm_cdn_frontdoor_profile" "lab" {   # the Front Door profile
  name                = "fd-order"              # the profile's name
  resource_group_name = azurerm_resource_group.lab.name   # which RG (the profile keeps its RG in v5)
  sku_name            = "Standard_AzureFrontDoor"   # the sku
}

resource "azurerm_cdn_frontdoor_origin_group" "lab" {   # the origin group (v5)
  name                = "fd-og-order"           # the group's name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.lab.id   # which profile (v5)

  load_balancing {                                # how traffic is spread (v5)
    sample_size               = 100                # probe 100% of origins
    successful_samples_required = 50               # this many good samples = healthy
  }
}

resource "azurerm_cdn_frontdoor_origin" "api" {   # the origin (the App Service)
  name                = "fd-origin-api"         # the origin's name
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.lab.id   # which group (v5)
  host_name           = azurerm_linux_web_app.api.default_hostname   # the App Service's hostname
  certificate_name_check_enabled = false          # don't validate the cert's name (lab)
}

resource "azurerm_cdn_frontdoor_endpoint" "lab" {   # the endpoint (the public hostname)
  name                = "fd-ep-order"           # the endpoint's name
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.lab.id   # which profile (v5)
}

resource "azurerm_cdn_frontdoor_route" "lab" {    # the route (path → origin group)
  name                = "fd-route-order"        # the route's name
  cdn_frontdoor_endpoint_id   = azurerm_cdn_frontdoor_endpoint.lab.id   # which endpoint (v5)
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.lab.id   # which origin group (v5)
  patterns_to_match   = ["/*"]                   # the path patterns
  supported_protocols = ["Http", "Https"]        # the protocols
  forwarding_protocol = "MatchRequest"           # forward using the request's protocol
}

resource "azurerm_servicebus_namespace" "lab" {  # the namespace
  name                = "sb-order"              # the namespace's name (globally unique)
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  sku                 = "Standard"              # the SKU (Standard = more features)
}

resource "azurerm_servicebus_topic" "orders" {   # the topic (fan-out)
  name                = "topic-orders"          # the topic's name
  namespace_id        = azurerm_servicebus_namespace.lab.id   # which namespace

}

resource "azurerm_servicebus_subscription" "worker" {   # the subscription (the Function's listener)
  name                = "sub-worker"            # the subscription's name
  topic_id            = azurerm_servicebus_topic.orders.id   # which topic
  max_delivery_count  = 10                      # the max delivery count
}

resource "random_string" "suffix" {              # a random suffix for the storage account
  length  = 8                                    # 8 characters
  special = false                                # no special chars
  lower = true                               # lowercase only
}

resource "azurerm_storage_account" "func" {      # the storage account (for the Function)
  name                = "storfunc${random_string.suffix.result}"   # a unique name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  account_tier            = "Standard"          # the tier
  account_replication_type = "LRS"              # the replication
  https_traffic_only_enabled = true             # force HTTPS
  min_tls_version         = "TLS1_2"            # the minimum TLS version
}

resource "azurerm_service_plan" "func" {         # the Function's plan
  name                = "asp-func"              # the plan's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  os_type             = "Linux"                 # the OS type
  sku_name            = "Y1"                    # the SKU (Y1 = Consumption)
}

resource "azurerm_linux_function_app" "worker" {   # the worker Function
  name                = "func-order-worker"     # the app's name (globally unique)
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  service_plan_id     = azurerm_service_plan.func.id   # which plan

  site_config {                                   # the site config (required in v5)
    always_on = false                           # no keep-alive
  }

  storage_account_name      = azurerm_storage_account.func.name   # which storage account
  storage_uses_managed_identity = true                  # use the identity (no key)

  identity {                                  # the app's identity
    type = "SystemAssigned"                   # a system-assigned identity
  }

  functions_extension_version = "~4"          # the host version
  https_only          = true                 # force HTTPS

  app_settings = {                            # the settings
    "FUNCTIONS_WORKER_RUNTIME" = "python"     # the worker runtime
    "SB_NAMESPACE"             = azurerm_servicebus_namespace.lab.name   # the Service Bus
    "COSMOS_ENDPOINT"          = azurerm_cosmosdb_account.lab.endpoint   # the Cosmos endpoint
  }
}

resource "azurerm_cosmosdb_account" "lab" {      # the account
  name                = "cosmos-order"          # the account's name (globally unique)
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  offer_type          = "Standard"              # the offer
  kind                = "GlobalDocumentDB"      # the kind (Core/SQL)

  consistency_policy {                          # the consistency level
    consistency_level = "Session"               # the level (Session = the default)
  }

  geo_location {                                # the location
    location          = "eastus"               # the region
    failover_priority = 0                       # the failover priority (0 = primary)
  }
}

resource "azurerm_cosmosdb_sql_database" "orders" {   # the database
  name                = "db-orders"             # the database's name
  resource_group_name = azurerm_resource_group.lab.name   # which RG
  account_name        = azurerm_cosmosdb_account.lab.name   # which account
  throughput          = 400                     # the provisioned throughput (RU/s)
}

resource "azurerm_cosmosdb_sql_container" "orders" {   # the container (SQL API)
  name                = "orders"                # the container's name
  resource_group_name = azurerm_resource_group.lab.name   # which RG
  account_name        = azurerm_cosmosdb_account.lab.name   # which account
  database_name       = azurerm_cosmosdb_sql_database.orders.name   # which database
  partition_key_paths = ["/customer"]           # the partition key
  throughput          = 400                     # the provisioned throughput (RU/s)
}

resource "azurerm_key_vault" "lab" {             # the Key Vault
  name                = "kv-order"              # the vault's name (globally unique)
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  tenant_id           = data.azurerm_client_config.current.tenant_id   # the tenant
  sku_name            = "standard"              # the SKU
  rbac_authorization_enabled = true             # RBAC (the v5 way)
}

resource "azurerm_key_vault_secret" "cosmos" {   # the Cosmos connection secret
  name                = "cosmos-connection"     # the secret's name
  key_vault_id        = azurerm_key_vault.lab.id   # which vault
  value               = "SuperSecret-123"       # the value (CHANGE)
}

resource "azurerm_user_assigned_identity" "func" {   # the identity for the Function
  name                = "id-func"               # the identity's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
}

resource "azurerm_role_assignment" "kv_officer" {   # grant the identity Secrets Officer
  scope                = azurerm_key_vault.lab.id   # on the vault
  role_definition_name = "Key Vault Secrets Officer"   # the role
  principal_id         = azurerm_user_assigned_identity.func.principal_id   # the identity
}

resource "azurerm_role_assignment" "cosmos_data" {   # grant the identity Cosmos Data Contributor
  scope                = azurerm_cosmosdb_account.lab.id   # on the Cosmos account
  role_definition_name = "Cosmos DB Data Contributor"   # the role
  principal_id         = azurerm_user_assigned_identity.func.principal_id   # the identity
}
