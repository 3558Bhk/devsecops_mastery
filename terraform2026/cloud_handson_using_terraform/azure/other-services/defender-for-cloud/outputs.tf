# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "pricing_tier" {                           # output: the subscription's tier
  value       = azurerm_security_center_subscription_pricing.lab.tier   # the tier
  description = "az security center subscription-pricing"   # inspect
}

output "defender_plan" {                          # output: the Defender plan
  value       = azurerm_security_center_storage_defender.lab.id   # the plan's id
  description = "az security center defender-plan list"   # inspect
}
