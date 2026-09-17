# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "default_hostname" {                       # output: the app's hostname
  value       = azurerm_linux_function_app.lab.default_hostname   # the hostname
  description = "https://<this>/api/<function>"                # the public URL
}

output "app_id" {                                 # output: the app's id
  value       = azurerm_linux_function_app.lab.id       # the id
  description = "az functionapp show -g rg-lab-func -n funcapp-lab"   # inspect
}
