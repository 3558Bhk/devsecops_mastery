# Terraform Databases — Azure SQL & Cosmos DB — Interview Questions

> **Cloud:** Azure · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~5 min

---

## Case A — Basic

**A1. What is Azure SQL in Terraform?**
**Answer:** A managed SQL Server + database: `azurerm_mssql_server` (the logical server) + `azurerm_mssql_database` (the database).

**A2. How do you declare an Azure SQL server?**
**Answer:** `resource "azurerm_mssql_server" "sql" { name = ... ; resource_group_name = ... ; location = ... ; version = "12.0" ; administrator_login = ... ; administrator_login_password = ... }`.

**A3. What is `azurerm_mssql_database`?**
**Answer:** The database itself, with `sku_name` (e.g. `Basic`, `S0`, `GP_Gen5_2`), `collation`, and `max_size_gb`.

**A4. What is a firewall rule in Azure SQL?**
**Answer:** `azurerm_mssql_firewall_rule` (or `azurerm_sql_firewall_rule`) — allows specific IP ranges to reach the server.

**A5. What is a Virtual Network rule?**
**Answer:** `azurerm_mssql_virtual_network_rule` — allows a subnet (via service endpoint) to access the server instead of public IPs.

**A6. What is a private endpoint for Azure SQL?**
**Answer:** `azurerm_private_endpoint` gives the server a private IP in your VNet, removing public exposure.

**A7. How do you protect the admin password?**
**Answer:** Reference Key Vault (`azurerm_key_vault_secret`/`data` lookup) or use Entra ID auth; mark the variable `sensitive`.

**A8. What is Cosmos DB in Terraform?**
**Answer:** `azurerm_cosmosdb_account` — a globally distributed NoSQL database with APIs (SQL/Core, MongoDB, Cassandra, Gremlin, Table).

**A9. How do you declare a Cosmos DB account?**
**Answer:** `resource "azurerm_cosmosdb_account" "db" { name = ... ; resource_group_name = ... ; location = ... ; offer_type = "Standard" ; kind = "GlobalDocumentDB" ; consistency_policy { consistency_level = "Session" } ; geo_location { location, failover_priority = 0 } }`.

**A10. What are Cosmos containers/databases in Terraform?**
**Answer:** `azurerm_cosmosdb_sql_database` + `azurerm_cosmosdb_sql_container` (with `partition_key_path` and `throughput`).

**A11. What is `offer_type` and `consistency_policy`?**
**Answer:** `offer_type` is the billing tier (Standard); `consistency_policy` sets the consistency level (Strong, BoundedStaleness, Session, ConsistentPrefix, Eventual).

**A12. What is a partition key in Cosmos DB?**
**Answer:** The property used to distribute data across physical partitions — declared via `partition_key_paths` on the container.

**A13. How do you scale Cosmos throughput?**
**Answer:** `throughput` (RU/s) on the database or container, or `autoscale_settings { max_throughput }` for automatic scaling.

**A14. What is `geo_location` and `failover_priority`?**
**Answer:** Defines the regions where the account replicates; priority 0 is the primary, and failover happens in priority order.

**A15. How do you get the connection string?**
**Answer:** `azurerm_mssql_database`/server outputs and Cosmos `primary_sql_connection_string`/`connection_strings` outputs.

## Case B — Advanced / Senior

**B1. How do you secure Azure SQL end-to-end with Terraform?**
**Answer:** Disable public access (`public_network_access_enabled = false`), add a private endpoint + private DNS zone, use Entra ID admins (`azurerm_mssql_server` `azuread_administrator`), enable transparent data encryption (`azurerm_mssql_transparent_data_encryption`) and auditing, and allow only app subnets.

**B2. What is the difference between DTU and vCore models for Azure SQL?**
**Answer:** DTU (`Basic`/`S0`…) is a bundled measure of compute+IO for simple workloads; vCore (`GP_Gen5_2`…) gives independent CPU/memory control and Hybrid Benefit. Choose by workload and licensing.

**B3. How do you implement geo-replication or failover groups for Azure SQL?**
**Answer:** `azurerm_mssql_failover_group` pairs a primary and secondary server (or database) with automatic failover, or `azurerm_mssql_database` `create_mode = "Secondary"` for geo-replicas.

**B4. How do you design Cosmos consistency vs availability tradeoffs?**
**Answer:** Strong = highest consistency, highest latency; Eventual = lowest latency; BoundedStaleness/Session balance. Pick based on whether stale reads are acceptable, and set it in `consistency_policy`.

**B5. What is autoscale throughput vs manual RU/s in Cosmos?**
**Answer:** Manual is a fixed RU/s (cheap if predictable); autoscale (`autoscale_settings`) scales 10%–100% of max automatically — better for spiky workloads. Combine with database-level (shared) throughput for multiple containers.

**B6. How do you design a partition key strategy?**
**Answer:** Choose a high-cardinality, evenly distributed key that matches query patterns (avoid hot partitions). Changing the partition key requires a new container + migration — get it right up front.

**B7. How do you enable Cosmos multi-region writes and conflict resolution?**
**Answer:** Multiple `geo_location` blocks with write enabled (or `capabilities`), plus a `conflict_resolution_policy` (LWW or custom) for multi-master setups.

**B8. How do you set up Azure SQL auditing and threat detection in Terraform?**
**Answer:** `azurerm_mssql_server_extended_auditing_policy` (to a storage account/Log Analytics) and `azurerm_mssql_server_security_alert_policy` for anomaly alerts.

**B9. How do you connect a private app to Azure SQL without public IPs?**
**Answer:** Private endpoint for the server, a private DNS zone linking `privatelink.database.windows.net`, and the app connecting to the private FQDN from a VNet-integrated host.

**B10. How do you use Terraform with Cosmos serverless vs provisioned throughput?**
**Answer:** Serverless accounts (`capabilities { name = "EnableServerless" }`) charge per operation with no fixed RU/s; provisioned is fixed/autoscale. Serverless suits low/unknown traffic.

**B11. What are the limits and gotchas of renaming/updating databases?**
**Answer:** Server/database/account names are often immutable (or trigger recreation). Plan names carefully, use `ignore_changes` for fields managed elsewhere, and migrate via restore/export when a rename is truly needed.

**B12. How do you structure database code across environments with modules?**
**Answer:** A database module (server, db, firewall/private endpoint, TDE, auditing, backup retention) instantiated per environment with different SKUs/tfvars, sharing naming and security conventions.

## Case C — Scenario

**C1. A scan flags your Azure SQL server as publicly accessible.**
**Answer:** Set `public_network_access_enabled = false`, add a private endpoint + DNS zone, and remove/limit firewall rules to app subnets only. Verify apps connect privately before fully closing public access.

**C2. You need automatic failover to another region for Azure SQL.**
**Answer:** Create a failover group with a secondary server in the target region and configure automatic failover policies; Terraform manages both servers and the failover group, and apps use the failover group listener.

**C3. Cosmos is throttling (429s) under load.**
**Answer:** Raise throughput (RU/s) or switch to autoscale, check for hot partitions (bad partition key), and optimize queries/indexing policy (`azurerm_cosmosdb_sql_container` `indexing_policy`).

**C4. You must keep 35 days of backups for compliance on Azure SQL.**
**Answer:** Set `azurerm_mssql_database` `short_term_retention_policy`/`long_term_retention_policy` accordingly (and enable TDE), then verify the retention is applied and audited.

**C5. You need to change the admin password without downtime.**
**Answer:** Rotate the secret in Key Vault and update the server (password changes apply without recreation), using Entra ID auth where possible to reduce password dependence.

**C6. Cosmos data must be queryable in a second region with low latency.**
**Answer:** Add a second `geo_location` with a failover priority (and optional multi-region writes), set consistency appropriate to the use case, and route clients to their local region's endpoint.
