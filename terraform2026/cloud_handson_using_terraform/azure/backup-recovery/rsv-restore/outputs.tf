# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "vault_name" {                             # output: the vault
  value       = azurerm_recovery_services_vault.lab.name    # the name
  description = "az recovery-services backup-vault show -g rg-lab-rsvrestore -n rsv-restore"   # inspect
}

output "restore_target_ip" {                      # output: the target's public IP
  value       = azurerm_public_ip.restore.ip_address        # the address
  description = "after the restore action, point DNS at this"   # the failover target
}
