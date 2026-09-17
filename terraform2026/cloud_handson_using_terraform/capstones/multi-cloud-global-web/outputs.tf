# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "aws_alb" {                               # output: the AWS ALB
  value       = aws_lb.web.dns_name                     # the name
  description = "the PRIMARY (AWS) endpoint"            # the primary
}

output "azure_app" {                             # output: the Azure App Service
  value       = azurerm_linux_web_app.app.default_hostname   # the hostname
  description = "the FAILOVER (Azure) endpoint"           # the failover
}

output "primary_record" {                        # output: the primary record
  value       = "primary.lab-mc.example.com"            # the record
  description = "the Route 53 PRIMARY (failover: failover.lab-mc.example.com)"   # the DNS
}
