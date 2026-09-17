output "namespace_host" {                         # output: the namespace endpoint
  value       = azurerm_servicebus_namespace.bus.endpoint   # e.g. msg-sb-2026.servicebus.windows.net
  description = "Clients connect to <host>/<entity>"   # how to use it
}

output "topic_name" {                             # output: the topic
  value       = azurerm_servicebus_topic.orders.name   # the name
  description = "Publish here; each subscription gets a copy"   # what it is
}

output "subscriptions" {                          # output: the subscription names
  value       = [azurerm_servicebus_subscription.billing.name, azurerm_servicebus_subscription.inventory.name]   # both subscriptions
  description = "billing, inventory"             # the consumers
}

output "queue_name" {                             # output: the queue
  value       = azurerm_servicebus_queue.archive.name   # the name
  description = "Work buffer with DLQ at 5 failed deliveries"   # what it is
}

output "rg_name" {                                # output: the resource group
  value       = azurerm_resource_group.msg.name      # the name
  description = "For az commands: -g <this>"        # handy
}
