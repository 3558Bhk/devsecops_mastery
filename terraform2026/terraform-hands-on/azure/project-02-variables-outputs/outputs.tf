output "storage_account_name" {                  # output: the account's name
  value       = azurerm_storage_account.app.name   # from the resource
  description = "Needed for az storage commands" # how you'll use it
}

output "blob_endpoint" {                         # output: the blob URL
  value       = azurerm_storage_account.app.primary_blob_endpoint   # e.g. https://<name>.blob.core.windows.net
  description = "Where files are stored"        # what it is
}

output "containers" {                            # output: the container names
  value       = [for c in azurerm_storage_container.app : c.name]   # for-expression: collect every container's name
  description = "What was created"             # sanity check after apply
}

output "environment" {                           # output: echo the input back
  value       = var.environment                  # straight from the variable
  description = "Sanity check: which environment this is"   # avoid building prod by accident
}
