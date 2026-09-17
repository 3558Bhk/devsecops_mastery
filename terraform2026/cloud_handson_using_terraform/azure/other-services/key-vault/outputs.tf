# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "vault_uri" {                               # output: the vault's URI
  value       = azurerm_key_vault.lab.vault_uri         # the URI
  description = "az keyvault secret show -g rg-lab-kv --vault-name kv-lab --name app-secret"   # read the secret
}

output "identity_principal_id" {                   # output: the identity's principal id
  value       = azurerm_user_assigned_identity.app.principal_id   # the principal id
  description = "the identity that now has Key Vault Secrets Officer on the vault"   # the grant
}
