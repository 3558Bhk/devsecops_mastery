# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "transit_gateway_id" {
  description = "The transit gateway's id (attach spokes to it)"
  value       = aws_ec2_transit_gateway.hub.id
}
