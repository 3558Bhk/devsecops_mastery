output "resource_group_name" {                   # output: the RG's name
  value       = azurerm_resource_group.first.name   # from the resource
  description = "Where everything in this project lives"   # what it is
}

output "storage_account_name" {                  # output: the storage account's name
  value       = azurerm_storage_account.first.name   # from the resource
  description = "The account you just created"    # what it is
}

output "blob_endpoint" {                         # output: the URL for blob storage
  value       = azurerm_storage_account.first.primary_blob_endpoint   # e.g. https://<name>.blob.core.windows.net
  description = "Use this to upload/download files"   # how you'll use it
}
