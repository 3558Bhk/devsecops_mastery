# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "profile_fqdn" {                          # output: the DNS name
  value       = "${azurerm_traffic_manager_profile.lab.dns_config[0].relative_name}.trafficmanager.net"   # the FQDN
  description = "point your DNS CNAME at this"   # the entry point
}
