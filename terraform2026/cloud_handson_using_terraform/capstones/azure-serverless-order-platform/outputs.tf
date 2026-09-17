# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "front_door_hostname" {                  # output: the Front Door hostname
  value       = azurerm_cdn_frontdoor_endpoint.lab.host_name   # the hostname
  description = "https://<this>  (the global entry point)"   # the URL
}

output "api_hostname" {                         # output: the App Service
  value       = azurerm_linux_web_app.api.default_hostname   # the hostname
  description = "https://<this>  (the order API)"   # the API
}

output "cosmos_endpoint" {                      # output: the Cosmos endpoint
  value       = azurerm_cosmosdb_account.lab.endpoint   # the endpoint
  description = "the Cosmos DB endpoint (use the connection string)"   # the store
}
