# ── DATABASE TIER: Azure SQL ───────────────────────────────────────────────────

resource "azurerm_mssql_server" "db" {              # the SQL server (a managed service, not a VM)
  name                         = "${var.project}sqlserver"   # globally unique, lowercase, e.g. capstsqlserver
  location                     = var.location               # same location
  resource_group_name          = azurerm_resource_group.capstone.name   # which group

  administrator_login          = "sqladmin"                   # the admin user
  administrator_login_password = var.sql_password             # from the sensitive variable
  minimum_tls_version          = "1.2"                        # require modern TLS
  version                      = "12.0"                       # SQL Server 2022
}

resource "azurerm_mssql_database" "db" {             # the database inside that server
  name      = "appdb"                                 # the database's name
  server_id = azurerm_mssql_server.db.id              # which server
  sku_name  = "Basic"                                 # the cheapest SKU
}
