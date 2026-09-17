# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "identity_client_id" {                  # output: the identity's client id
  value       = azurerm_user_assigned_identity.storage.client_id   # the client id
  description = "the principal that was granted Storage Blob Data Owner"   # the identity
}

output "vm_name" {                             # output: the VM
  value       = azurerm_linux_virtual_machine.consumer.name   # the name
  description = "az vm identity list -g rg-lab-identity -n vm-consumer"   # inspect
}
