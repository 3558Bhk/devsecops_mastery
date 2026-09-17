# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "web_url" {
  description = "The web app URL"
  value       = azurerm_linux_web_app.orders.default_hostname   # the default hostname (v5 attr)
}

output "sql_fqdn" {
  description = "The SQL server FQDN"
  value       = azurerm_mssql_server.orders.fully_qualified_domain_name   # the FQDN (v5 attr name)
}

output "vault_uri" {
  description = "The Key Vault URI"
  value       = azurerm_key_vault.lab.vault_uri
}
