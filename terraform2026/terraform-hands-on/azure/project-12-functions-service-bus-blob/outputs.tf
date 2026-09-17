output "namespace_name" {                         # output: the Service Bus namespace
  value       = azurerm_servicebus_namespace.bus.name   # the name
  description = "az servicebus topic send-topic-message --namespace-name <this>"   # publish an order
}

output "namespace_endpoint" {                     # output: the endpoint clients connect to
  value       = azurerm_servicebus_namespace.bus.endpoint   # e.g. func-sb-2026.servicebus.windows.net
  description = "the connection string's host part"         # what it is
}

output "function_name" {                          # output: the function app's name
  value       = azurerm_linux_function_app.app.name       # the name
  description = "its host: https://<this>.azurewebsites.net"   # the function URL
}

output "rg_name" {                                # output: the resource group
  value       = azurerm_resource_group.app.name      # the name
  description = "For az commands: -g <this>"        # handy
}
