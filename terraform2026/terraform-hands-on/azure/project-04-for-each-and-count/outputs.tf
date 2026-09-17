output "vm_names" {                                # output: all VM names as a list
  value       = azurerm_linux_virtual_machine.vm[*].name   # splat [*]: collect from every item
  description = "The VMs Terraform created"        # sanity check
}

output "nic_names" {                               # output: all NIC names as a list
  value       = azurerm_network_interface.vm[*].name       # one per VM
  description = "The NICs, one per VM"            # shows the 1:1 pairing
}

output "rule_names" {                              # output: all NSG rule names
  value       = [for r in azurerm_network_security_rule.rules : r.name]   # for-expression over the map
  description = "allow-ssh, allow-http, ..."      # shows the for_each keys
}
