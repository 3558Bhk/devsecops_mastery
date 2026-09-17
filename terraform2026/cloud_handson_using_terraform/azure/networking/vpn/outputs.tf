# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "gateway_ip" {                               # output: the cloud public IP
  value       = azurerm_public_ip.gw.ip_address             # the address
  description = "configure this + the shared key on the on-prem device"   # connect
}
