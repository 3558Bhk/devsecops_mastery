# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "vault_name" {                             # output: the vault
  value       = azurerm_recovery_services_vault.lab.name    # the name
  description = "az recovery-services backup-vault show -g rg-lab-rsv -n rsv-lab"   # inspect
}

output "protected_vm" {                           # output: the protected VM
  value       = azurerm_backup_protected_vm.lab.protection_state   # the state
  description = "the protection state (Protected)"   # verify
}
