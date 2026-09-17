# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "built_ami_id" {                           # output: the new AMI
  value       = aws_ami.golden.id                   # the id
  description = "use this id in a launch template / ASG / other instances"   # the golden image
}

output "lookup_ami_id" {                          # output: the looked-up base image
  value       = data.aws_ami.al2023.id               # the id
  description = "what we started from"                # for comparison
}
