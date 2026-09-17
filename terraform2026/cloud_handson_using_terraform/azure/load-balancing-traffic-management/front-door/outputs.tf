# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "endpoint_hostname" {                      # output: the public hostname
  value       = azurerm_cdn_frontdoor_endpoint.lab.host_name   # the hostname (v5 attr)   # the hostname
  description = "point your DNS CNAME at this"   # the entry point
}
