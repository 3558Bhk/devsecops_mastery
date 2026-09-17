output "appgw_ip" {                                 # output: the App Gateway's public IP
  value       = azurerm_public_ip.appgw.ip_address    # the IP to hit
  description = "curl http://this → the web page"   # how to test
}

output "sql_server" {                                # output: the SQL server's FQDN
  value       = azurerm_mssql_server.db.fully_qualified_domain_name   # e.g. capstsqlserver.database.windows.net
  description = "az sql db tsql query -s this -d appdb -q \"SELECT 1\""   # how to test
}

output "vault_name" {                                # output: the vault's name
  value       = azurerm_key_vault.secrets.name          # from the resource
  description = "az keyvault secret show --name db-password --vault-name this"   # how to read the secret
}

output "rg_name" {                                   # output: the resource group's name
  value       = azurerm_resource_group.capstone.name    # from the resource
  description = "For az commands: -g this"            # handy for lookups
}
