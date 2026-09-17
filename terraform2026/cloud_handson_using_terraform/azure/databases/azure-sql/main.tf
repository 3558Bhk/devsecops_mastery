# ============================================================================
#  Azure SQL — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {      # the resource group
  name     = "lab-rg"                   # its name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_mssql_server" "lab" {       # the Azure SQL server (a logical DB container)
  name                         = "labsqldb"          # the server name (GLOBAL — must be unique across ALL of Azure)
  resource_group_name          = azurerm_resource_group.lab.name   # which resource group
  location                     = azurerm_resource_group.lab.location   # which region
  version                      = "12.0"              # SQL version 12 (2016) — a common baseline

  administrator_login          = "sqladmin"          # the admin username
  administrator_login_password = "Lab@Sql123"        # ⚠️ DUMMY password — temp only, strong + rotated

  minimum_tls_version                  = "1.2"       # only TLS 1.2+ for connections
  public_network_access_enabled        = true        # the internet can reach it (false = private endpoints only)
  # NOTE: in v5 the per-server firewall defaults are handled by explicit rules below (the old
  # "default_rule" concept is gone) — so we create the rules we actually need.

  tags = {
    environment = "lab"                      # the environment
  }
}

resource "azurerm_mssql_firewall_rule" "myip" {  # the firewall rule (a server-level CIDR allow)
  name        = "my-laptop"                     # the rule name
  server_id   = azurerm_mssql_server.lab.id    # which server (v5: the server id)
  start_ip_address = "0.0.0.0"                 # the start of the range (0.0.0.0)
  end_ip_address   = "0.0.0.0"                 # the end of the range (0.0.0.0)
  # ⚠️ 0.0.0.0/0 = OPEN TO THE WHOLE INTERNET — a lab shortcut.
  # In real life: put ONLY your office/static IP here, or 0.0.0.0/0 is a textbook security finding.
}

resource "azurerm_mssql_database" "orders" {    # the database (lives INSIDE the server)
  name      = "orders"                          # the DB name
  server_id = azurerm_mssql_server.lab.id      # which server it belongs to (v5: the server id)

  sku_name  = "GP_S_Gen5_1"                    # the General Purpose tier, Gen5, 1 vCore (~2GB RAM)
  collation = "SQL_Latin1_General_CP1_CI_AS"   # the sort/case rules (case-insensitive, the Windows default)

  storage_account_type = "Local"                 # locally redundant storage (3 copies in one region)
  zone_redundant       = false                 # (LRS) not zone-redundant
}
