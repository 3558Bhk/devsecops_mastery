# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "gateway_url" {                           # output: the gateway's URL
  value       = azurerm_api_management.lab.gateway_url   # the gateway's URL
  description = "https://<this>/lab  (the API lives under the /lab path)"   # the entry point
}

output "api_id" {                                # output: the API's id
  value       = azurerm_api_management_api.lab.id       # the id
  description = "az apim api show -g rg-lab-apim -s apim-lab -n api-lab"   # inspect
}
