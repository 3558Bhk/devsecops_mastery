# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "accelerator_dns_name" {
  description = "The Global Accelerator's anycast DNS name (route traffic here)"
  value       = aws_globalaccelerator_accelerator.lab.dns_name
}
