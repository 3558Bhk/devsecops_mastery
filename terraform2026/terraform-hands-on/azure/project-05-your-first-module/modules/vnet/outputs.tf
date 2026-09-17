# The MODULE's outputs — the root reads these as module.vnet.<name>.

output "vnet_name" {                              # the VNet's name
  value = azurerm_virtual_network.this.name       # from the resource
}

output "subnets" {                                # all subnet IDs, keyed by purpose
  value = { for s in azurerm_subnet.this : s.name => s.id }   # for-expression: name → id for each
}
