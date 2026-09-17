output "cosmos_name" {                            # output: the Cosmos account name
  value       = azurerm_cosmosdb_account.orders.name   # the name
  description = "az cosmosdb sql query --account-name <this>"   # how to query
}

output "cosmos_endpoint" {                        # output: the Cosmos endpoint
  value       = azurerm_cosmosdb_account.orders.endpoint   # e.g. https://cosmos-cosmos-2026.documents.azure.com:443/
  description = "What the app connects to"       # what it is
}

output "vault_name" {                             # output: the vault's name
  value       = azurerm_key_vault.secrets.name       # the name
  description = "az keyvault secret show --name db-password --vault-name <this>"   # how to read the secret
}

output "app_name" {                               # output: the web app's name
  value       = azurerm_linux_web_app.app.name         # the name
  description = "az webapp identity show -n <this>"   # check the managed identity
}

output "app_url" {                                # output: the web app's hostname
  value       = azurerm_linux_web_app.app.default_hostname   # e.g. cosmos-vault-web.azurewebsites.net
  description = "curl -sI https://<this>"         # the app (empty F1 app) responds 200
}

output "rg_name" {                                # output: the resource group
  value       = azurerm_resource_group.app.name      # the name
  description = "For az commands: -g <this>"        # handy
}
