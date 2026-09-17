# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "endpoint" {                               # output: how to connect
  value       = aws_db_instance.mysql.endpoint      # host:port
  description = "mysql -h <this> -u labadmin -p"   # the connection
}

output "db_password" {                            # output: the generated password
  value       = random_password.db.result           # the value
  description = "shown ONCE in the output block"   # treat it like a secret
  sensitive   = true                                 # mask it in plan/apply
}
