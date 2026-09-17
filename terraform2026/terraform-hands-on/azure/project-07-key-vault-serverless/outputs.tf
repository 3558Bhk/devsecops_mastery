output "vault_name" {                             # output: the vault's name
  value       = azurerm_key_vault.vault.name        # from the resource
  description = "Use with: az keyvault secret show --vault-name <this>"   # how to test
}

output "vault_uri" {                              # output: the vault's full URI
  value       = azurerm_key_vault.vault.vault_uri   # e.g. https://kvlkvdev.vault.azure.net/
  description = "The base URL of the vault"       # what apps use to find it
}

output "app_url" {                                # output: the web app's URL
  value       = azurerm_linux_web_app.app.default_hostname   # e.g. kvl-web.azurewebsites.net
  description = "curl -sI https://<this> → expect 200"   # how to test
}

output "secret_name" {                            # output: the secret's name
  value       = azurerm_key_vault_secret.app_secret.name   # from the resource
  description = "az keyvault secret show --name <this> --vault-name $(terraform output -raw vault_name)"   # how to read it
}
