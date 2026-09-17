# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "server_fqdn" {
  description = "The SQL server FQDN"
  value       = azurerm_mssql_server.lab.fully_qualified_domain_name   # e.g. labsqldb.database.windows.net (v5 attr name)
}

output "db_name" {
  description = "The database name"
  value       = azurerm_mssql_database.orders.name
}
