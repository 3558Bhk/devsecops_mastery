output "main_account" {                           # output: the project's account name
  value       = azurerm_storage_account.main.name  # from the resource
  description = "The storage account this project manages"   # what it is
}

output "legacy_account" {                         # output: the imported account's name
  value       = azurerm_storage_account.legacy.name   # after import, this now has a value
  description = "The account we adopted with terraform import"   # proves the import worked
}
