# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "primary_url" {
  description = "The AWS primary URL"
  value       = "http://${aws_eip.web.public_ip}"
}

output "standby_url" {
  description = "The Azure standby URL"
  value       = "https://${azurerm_linux_web_app.standby.default_hostname}"
}

output "failover_record" {
  description = "The failover DNS name"
  value       = aws_route53_record.failover.fqdn
}
