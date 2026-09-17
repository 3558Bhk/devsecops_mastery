output "gateway_url" {                            # output: the gateway's base URL
  value       = azurerm_api_management.gw.gateway_url   # e.g. https://apim-apim-2026.azure-api.net
  description = "the developer portal is at <this>/developer"   # manage products/subscriptions here
}

output "api_url" {                                # output: the PUBLIC url of the hello API
  value       = "${azurerm_api_management.gw.gateway_url}${azurerm_api_management_api.hello.path}"   # base + path
  description = "curl <this> (add Ocp-Apim-Subscription-Key if you require subscriptions)"   # how to call it
}

output "apim_name" {                              # output: the gateway's name
  value       = azurerm_api_management.gw.name       # the name
  description = "az api-management show -n <this> (wait for state=Running)"   # health check
}

output "rg_name" {                                # output: the resource group
  value       = azurerm_resource_group.api.name      # the name
  description = "For az commands: -g <this>"        # handy
}
