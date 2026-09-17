# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "table_name" {                             # output: the table
  value       = aws_dynamodb_table.orders.name     # the name
  description = "aws dynamodb scan --table-name <this>"   # peek at the data
}

output "gsi_name" {                               # output: the index
  value       = "StatusIndex"                       # the name
  description = "query it with --key-condition-expression \"status = :s\""   # the other view
}
