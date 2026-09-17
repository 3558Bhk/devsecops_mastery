# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "identity_principal_id" {                # output: the principal id
  value       = azurerm_user_assigned_identity.storage.principal_id   # the principal id
  description = "the principal that now has Storage Blob Data Owner on the account"   # the grant
}

output "storage_account" {                       # output: the account
  value       = azurerm_storage_account.lab.name          # the name
  description = "the account the identity can access"   # the target
}
