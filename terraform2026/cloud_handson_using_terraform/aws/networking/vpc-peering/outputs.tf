# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "peering_connection_id" {
  description = "The peering connection's id (the wire between the VPCs)"
  value       = aws_vpc_peering_connection.a_to_b.id
}
