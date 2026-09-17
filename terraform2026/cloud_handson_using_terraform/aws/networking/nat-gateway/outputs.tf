# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "nat_public_ip" {
  description = "The NAT gateway's public IP"
  value       = aws_eip.nat.public_ip
}

output "nat_gateway_id" {
  description = "The NAT gateway's id"
  value       = aws_nat_gateway.nat.id
}
