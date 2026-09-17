# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "role_arn" {                               # output: the role
  value       = aws_iam_role.lab.arn                # the ARN
  description = "attach it to a Lambda/EC2: role = <this>"               # how a service uses it
}
