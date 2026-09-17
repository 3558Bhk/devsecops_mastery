# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "nsg_name" {                               # output: the NSG
  value       = azurerm_network_security_group.intro.name       # the name
  description = "az network nsg list-rule -g rg-lab-nsg -n nsg-intro   (see the default rules)"   # inspect
}
