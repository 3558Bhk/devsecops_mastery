# ============================================================================
#  Capstone 3 — Azure Landing Zone (hub & spoke, governed)
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "prod" {        # the group
  name     = "landzone-prod"                      # its name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_virtual_network" "prod" {       # the prod VNet
  name                = "vnet-prod"               # its name
  location            = "eastus"
  resource_group_name = azurerm_resource_group.prod.name
  address_space       = ["10.0.0.0/16"]           # the CIDR
}

resource "azurerm_subnet" "web" {                  # the web subnet (separate resource in v5)
  name                 = "subnet-prod-web"         # its name
  resource_group_name  = azurerm_resource_group.prod.name
  virtual_network_name = azurerm_virtual_network.prod.name   # which VNet
  address_prefixes     = ["10.0.1.0/24"]           # the CIDR
}

resource "azurerm_network_security_group" "web" { # the NSG (a rule container)
  name                = "nsg-prod-web"
  resource_group_name = azurerm_resource_group.prod.name
  location            = azurerm_resource_group.prod.location
}

resource "azurerm_network_security_rule" "https" { # the HTTPS allow
  name                        = "allow-https"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.prod.name
  network_security_group_name = azurerm_network_security_group.web.name
}

resource "azurerm_subnet_network_security_group_association" "web" { # the association (separate in v5)
  subnet_id                 = azurerm_subnet.web.id
  network_security_group_id = azurerm_network_security_group.web.id
}

resource "azurerm_log_analytics_workspace" "lab" { # the workspace
  name                = "law-landzone"
  resource_group_name = azurerm_resource_group.prod.name
  location            = azurerm_resource_group.prod.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_action_group" "team" {   # who gets paged
  name                = "ag-team"
  resource_group_name = azurerm_resource_group.prod.name
  short_name          = "team"
  email_receiver {                          # the email receiver (v5: email_receiver block)
    name    = "team"
    email_address = "devs@example.com"        # ⚠️ DUMMY (v5: email_address)
  }
}

resource "azurerm_monitor_metric_alert" "cpu" {    # the alert (CPU > 80% for 5 min)
  name                = "cpu-high"
  resource_group_name = azurerm_resource_group.prod.name
  scopes              = [azurerm_linux_web_app.orders.id]
  description         = "CPU is high on the orders app"

  criteria {
    metric_namespace = "webserver"
    metric_name      = "CPU Percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.team.id
  }
}

resource "azurerm_service_plan" "app" {           # the plan (B1)
  name                = "asp-prod"
  resource_group_name = azurerm_resource_group.prod.name
  location            = azurerm_resource_group.prod.location
  os_type             = "Linux"
  sku_name            = "B1"
}

resource "azurerm_linux_web_app" "orders" {       # the web app
  name                       = "app-landzone-orders"
  resource_group_name        = azurerm_resource_group.prod.name
  service_plan_id            = azurerm_service_plan.app.id
  location                   = azurerm_resource_group.prod.location
  https_only                 = true

  site_config {                                   # the site config (required in v5)
    always_on = false                           # no keep-alive
  }

  app_settings = {                                # the app settings (v5: top-level map)
    "SQL_DATABASE" = "orders"
    "KV_NAME"      = azurerm_key_vault.lab.name
  }
}

resource "azurerm_mssql_server" "orders" {        # the server
  name                         = "landzone-sql"
  resource_group_name          = azurerm_resource_group.prod.name
  location                     = azurerm_resource_group.prod.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = "Lab@Sql123"     # ⚠️ DUMMY
  minimum_tls_version          = "1.2"
  public_network_access_enabled = true
}

resource "azurerm_mssql_database" "orders" {      # the DB
  name      = "orders"
  server_id = azurerm_mssql_server.orders.id
  sku_name  = "GP_S_Gen5_1"
  collation = "SQL_Latin1_General_CP1_CI_AS"
  storage_account_type = "Local"                # LRS equivalent (v5 enum: Geo/GeoZone/Local/Zone)
}

resource "azurerm_mssql_firewall_rule" "app" {    # allow the app (v5: explicit rule)
  name           = "allow-app-service"
  server_id      = azurerm_mssql_server.orders.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"                    # ⚠️ DUMMY (open) — use the app's egress range in real life
}

resource "azurerm_key_vault" "lab" {              # the vault
  name                = "kv-landzone"
  resource_group_name = azurerm_resource_group.prod.name
  location            = azurerm_resource_group.prod.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"
  rbac_authorization_enabled = false            # key access via access policies (v5: required flag)

  access_policy {
    tenant_id      = data.azurerm_client_config.current.tenant_id
    object_id      = data.azurerm_client_config.current.object_id
    secret_permissions = ["Get", "Set", "List"]
  }
}

resource "azurerm_key_vault_secret" "sqlpw" {     # a secret
  name         = "sql-admin-password"
  value        = "Lab@Sql123"                     # ⚠️ DUMMY
  key_vault_id = azurerm_key_vault.lab.id
}

data "azurerm_client_config" "current" {}         # "me" (the logged-in user)

# ── Outputs ──────────────────────────────────────────────────────────────
