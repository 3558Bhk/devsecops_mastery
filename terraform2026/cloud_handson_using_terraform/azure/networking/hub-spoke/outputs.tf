# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "peerings" {                                 # output: the peering names
  value = [                                           # all four
    azurerm_virtual_network_peering.hub_to_a.name,   # hub→A
    azurerm_virtual_network_peering.a_to_hub.name,   # A→hub
    azurerm_virtual_network_peering.hub_to_b.name,   # hub→B
    azurerm_virtual_network_peering.b_to_hub.name,   # B→hub
  ]
  description = "the four one-way peering links forming two bidirectional links"   # the set
}
