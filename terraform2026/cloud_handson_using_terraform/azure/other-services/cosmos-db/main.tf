# ============================================================================
#  Cosmos DB — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-lab-cosmos"                     # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_cosmosdb_account" "lab" {      # the account
  name                = "cosmos-lab"            # the account's name (globally unique)
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  offer_type          = "Standard"              # the offer (Standard)
  kind                = "GlobalDocumentDB"      # the kind (Core/SQL API)

  consistency_policy {                          # the consistency level (Session = the default)
    consistency_level = "Session"               # the level (Strong/Bounded/Session/Prefix/Eventual)
  }

  geo_location {                                # the location(s) (single region here)
    location          = "eastus"               # the region
    failover_priority = 0                       # the failover priority (0 = primary)
  }
}

resource "azurerm_cosmosdb_sql_database" "lab" {   # the database
  name                = "db-lab"                # the database's name
  resource_group_name = azurerm_resource_group.lab.name   # which RG
  account_name        = azurerm_cosmosdb_account.lab.name   # which account
  throughput          = 400                     # the provisioned throughput (RU/s)
}

resource "azurerm_cosmosdb_sql_container" "orders" {   # the container (SQL API)
  name                = "orders"                # the container's name
  resource_group_name = azurerm_resource_group.lab.name   # which RG
  account_name        = azurerm_cosmosdb_account.lab.name   # which account
  database_name       = azurerm_cosmosdb_sql_database.lab.name   # which database
  partition_key_paths = ["/customer"]           # the partition key (the sharding key)
  throughput          = 400                     # the provisioned throughput (RU/s)
}
