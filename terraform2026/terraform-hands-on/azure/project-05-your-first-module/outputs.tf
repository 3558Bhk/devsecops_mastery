output "vnet_name" {                                # root output: the VNet's name (from the module)
  value       = module.vnet.vnet_name                # module.vnet = the call, .vnet_name = its output
  description = "The VNet the module created"       # what it is
}

output "subnets" {                                  # root output: all subnet IDs, keyed by purpose
  value       = module.vnet.subnets                  # a map: { web = "...", app = "...", data = "..." }
  description = "Use these to place resources per tier"   # e.g. module.vnet.subnets["app"]
}

output "vm_name" {                                   # root output: the proof VM
  value       = azurerm_linux_virtual_machine.vm.name   # from the root's own resource
  description = "Sits inside the module's web subnet"   # proves the wiring works
}
