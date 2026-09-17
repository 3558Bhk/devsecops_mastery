# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "public_ip" {                           # output: the VM's public IP
  value       = azurerm_public_ip.vm.ip_address         # the address
  description = "ssh azureadmin@<this>"                  # connect
}

output "vm_id" {                               # output: the VM's id
  value       = azurerm_linux_virtual_machine.web.id    # the id
  description = "az vm show -g rg-lab-vm -n vm-lab"      # inspect
}
