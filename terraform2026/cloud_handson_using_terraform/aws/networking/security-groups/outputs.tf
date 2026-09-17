# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "app_sg_id" {
  description = "The app security group's id"
  value       = aws_security_group.app.id
}

output "db_sg_id" {
  description = "The DB security group's id"
  value       = aws_security_group.db.id
}
