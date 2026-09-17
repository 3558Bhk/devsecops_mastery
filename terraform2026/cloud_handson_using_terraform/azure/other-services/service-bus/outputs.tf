# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "namespace_endpoint" {                     # output: the namespace's endpoint
  value       = azurerm_servicebus_namespace.lab.endpoint   # the endpoint
  description = "the Service Bus endpoint (use the connection string to send/receive)"   # connect
}

output "queue_name" {                             # output: the queue
  value       = azurerm_servicebus_queue.work.name        # the name
  description = "az servicebus queue show -g rg-lab-sb -n sb-lab -q queue-work"   # inspect
}
