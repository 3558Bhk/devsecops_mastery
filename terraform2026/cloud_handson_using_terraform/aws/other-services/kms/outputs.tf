# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "alias_name" {                             # output: the alias
  value       = aws_kms_alias.app.name               # alias/lab-app
  description = "use this (not the key ARN) in aws kms encrypt --key-id alias/lab-app"   # stable
}
