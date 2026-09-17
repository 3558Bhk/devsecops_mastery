# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "secret_name" {                             # output: the secret
  value       = aws_secretsmanager_secret.db.name       # the name
  description = "aws secretsmanager get-secret-value --secret-id lab/db-credentials"   # read it
}
