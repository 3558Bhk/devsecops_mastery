# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "nlb_dns_name" {
  description = "The NLB's public DNS name (point a domain here)"
  value       = aws_lb.web.dns_name
}
