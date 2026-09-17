# Azure 6 — Databases (Azure SQL, Flexible Server, Cosmos DB)

> **⏱️ Time to complete: ~75 min** (read + create an Azure SQL server + a Cosmos DB account)

## 6.1 Azure SQL (managed relational)

```hcl
locals {                                      # named expressions
  # SQL server name: globally unique, lowercase, digits, '-'
  sql_server_name = lower(replace("${var.project}-${var.environment}-sql", "_", "-"))   # e.g. "webapp-dev-sql"
}

resource "azurerm_mssql_server" "main" {      # an Azure SQL server
  name                         = local.sql_server_name   # the name (globally unique)
  location                     = azurerm_resource_group.main.location   # the location
  resource_group_name          = azurerm_resource_group.main.name   # the RG
  administrator_login          = "sqladmin"     # the admin user
  administrator_login_password = random_password.sql.result   # the admin password
  version                      = "12.0"          # (SQL version)
  minimum_tls_version          = "1.2"           # minimum TLS
  tags                         = local.common_tags   # the common tags
}

# Firewall: allow the app subnet (or your IP for testing)
resource "azurerm_mssql_firewall_rule" "app" {   # a firewall rule
  name             = "app-subnet"                   # the rule name
  resource_group_name = azurerm_resource_group.main.name   # the RG
  server_name      = azurerm_mssql_server.main.name   # the server
  start_ip_address = "10.0.1.0"                     # the start IP
  end_ip_address   = "10.0.1.255"                   # the end IP
}

resource "azurerm_mssql_database" "app" {        # an Azure SQL database
  name      = "app"                              # the database name
  resource_group_name = azurerm_resource_group.main.name   # the RG
  server_id = azurerm_mssql_server.main.id       # the server
  sku_name  = "Standard"            # (GP/GPv2 series; or "Premium")
  max_size_gb = 250                          # auto-grow storage to 250 GB
  zone_redundant = (var.environment == "prod")   # HA across AZs (prod)
  tags = local.common_tags                     # the common tags
}
```

### SQL knobs that matter
- **`sku_name`**: dev = `Basic`/`GP_Gen5_1`; prod = `Standard`/`GP_Gen5_2`+ (or **serverless** for spiky workloads).
- **`max_size_gb`**: auto-grow storage.
- **`zone_redundant`**: HA across AZs (prod).
- **Firewall**: restrict to the app subnet (or use **private endpoint** for full private access).
- **Managed identity** for auth (the app authenticates via its identity, not a password) — the modern pattern.

## 6.2 Flexible Server (MySQL / PostgreSQL — simpler)

```hcl
resource "azurerm_mysql_flexible_server" "main" {   # a MySQL flexible server
  name                = "${local.name_prefix}-mysql"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  administrator_login = "adminuser"            # the admin user
  administrator_login_password = random_password.mysql.result   # the admin password
  sku_name            = "GP_Standard_D4s_v3"   # the SKU
  storage_mb          = 32768                  # 32 GB storage
  version             = "8.0"                  # the MySQL version
  zone_redundant      = (var.environment == "prod")   # HA (prod)
  backup_retention_days = 7                     # 7-day backup retention
  tags = local.common_tags                     # the common tags
}

resource "azurerm_mysql_flexible_database" "app" {   # a database on the server
  name      = "app"                              # the database name
  server_id = azurerm_mysql_flexible_server.main.id   # the server
}
```
- **Flexible server** = simpler, cheaper, per-DVU pricing; good for MySQL/Postgres without the Azure SQL overhead.
- **PostgreSQL**: `azurerm_postgresql_flexible_server` / `azurerm_postgresql_flexible_database` (same shape).

## 6.3 Cosmos DB (managed NoSQL)

```hcl
resource "azurerm_cosmosdb_account" "main" {   # a Cosmos DB account
  name                = "${local.name_prefix}-cosmos"   # the name
  location            = azurerm_resource_group.main.location   # the location
  resource_group_name = azurerm_resource_group.main.name   # the RG
  offer_throughput    = 400           # (RU/s) — or use auto_pilot (autoscale)
  kind                = "GlobalDocumentDB"   # the API kind
  consistency_level   = "Session"     # Strong | BoundedStaleness | Session | ConsistentPrefix | Eventual
  locations {                                # a location
    location           = azurerm_resource_group.main.location   # the location
    failover_priority  = 0                    # the failover priority (0 = primary)
  }
  capabilities {                             # a capability
    name = "EnableMongo"   # (only if using the Mongo API)
  }
  tags = local.common_tags                   # the common tags
}

resource "azurerm_cosmosdb_sql_database" "app" {   # a SQL database in the account
  name  = "app"                              # the database name
  resource_group_name = azurerm_resource_group.main.name   # the RG
  account_id = azurerm_cosmosdb_account.main.id   # the account
}

resource "azurerm_cosmosdb_container" "orders" {   # a container in the database
  name                = "orders"                   # the container name
  resource_group_name = azurerm_resource_group.main.name   # the RG
  account_id          = azurerm_cosmosdb_account.main.id   # the account
  database_name       = azurerm_cosmosdb_sql_database.app.name   # the database
  partition_key_path  = "/customer_id"             # the partition key
  throughput          = 400                        # the throughput (RU/s)
}
```

- **Cosmos DB** = globally-distributed NoSQL (document, key-value, graph, table, Mongo APIs).
- **`offer_throughput`** (provisioned RU/s) vs **`auto_pilot`** (autoscale, spiky).
- **`consistency_level`** = your consistency guarantee (default `Session` is a good balance).
- **`partition_key_path`** = the container's partition key (choose wisely — it drives scaling).

## 6.4 Choosing the Database

| Need | Pick |
|---|---|
| Standard relational (T-SQL), HA | **Azure SQL** |
| Simpler/cheaper MySQL or Postgres | **Flexible Server** |
| Globally-distributed NoSQL, multi-API | **Cosmos DB** |
| Analytical / OLAP | **Synapse** / **Fabric** |
| Search | **Azure AI Search** |
| Cache | **Azure Cache for Redis** |

## 6.5 Getting It Right / Gotchas

- **SQL server name is globally unique** → `uuidv5` or prefix.
- **Firewall** (or **private endpoint**) — never expose SQL publicly.
- **`zone_redundant`** for HA (prod).
- **`max_size_gb`** to avoid disk-full.
- **Managed identity** for DB auth (keyless) — the modern pattern.
- **Flexible server** = simpler/cheaper for MySQL/Postgres.
- **Cosmos** = globally-distributed NoSQL; `partition_key_path` is critical; provisioned vs `auto_pilot`.
- **`version`** pin (SQL/MySQL/Postgres) to avoid silent upgrades.
- **Secrets**: admin password in a **Key Vault** (not state, ideally).

## 6.6 Interview Quick Facts

- **Azure SQL** = managed relational (T-SQL); server + database + firewall.
- **Flexible Server** = simpler MySQL/Postgres (per-DVU).
- **Cosmos DB** = globally-distributed NoSQL (multi-API, consistency levels, partition key).
- **`zone_redundant`** = HA across AZs.
- **Firewall / Private Endpoint** = never public.
- **Managed identity** = keyless DB auth.
- **Globally unique names**: SQL server (and storage, key vault).
