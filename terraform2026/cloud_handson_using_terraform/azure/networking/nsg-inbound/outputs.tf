# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "nsg_rules" {                              # output: the rule names
  value       = [for r in azurerm_network_security_group.inbound.security_rule : r.name]   # each rule's name
  description = "the three inbound rules, in priority order"   # the set
}
