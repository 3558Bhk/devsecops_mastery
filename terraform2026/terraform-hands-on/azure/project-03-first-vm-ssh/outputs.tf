output "public_ip" {                                # output: the VM's public IP
  value       = azurerm_public_ip.vm.ip_address      # the actual IP address
  description = "SSH into the VM with this"        # what it's for
}

output "ssh_command" {                              # output: a ready-to-paste ssh command
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.vm.ip_address}"   # built from the inputs + the IP
  description = "Copy-paste this into a terminal"   # the exact command to run
}

output "vm_name" {                                  # output: the VM's name
  value       = azurerm_linux_virtual_machine.vm.name   # from the resource
  description = "Useful for az vm list / portal lookups"   # for debugging
}
