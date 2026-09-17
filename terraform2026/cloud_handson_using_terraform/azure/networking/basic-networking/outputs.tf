# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "vnet_name" {                              # output: the VNet
  value       = azurerm_virtual_network.lab.name          # the name
  description = "az network vnet show -g rg-lab-net -n vnet-lab"   # inspect
}

output "public_ip" {                              # output: the public IP
  value       = azurerm_public_ip.web.ip_address            # the address
  description = "the address a future VM / gateway can use"    # ready
}
