# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "endpoint" {                              # output: the account's endpoint
  value       = azurerm_cosmosdb_account.lab.endpoint   # the endpoint
  description = "the account's endpoint (use the connection string to connect)"   # connect
}

output "container" {                             # output: the container
  value       = azurerm_cosmosdb_sql_container.orders.name      # the name
  description = "az cosmosdb sql container list -g rg-lab-cosmos -a cosmos-lab -d db-lab"   # inspect
}
