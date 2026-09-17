# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "asg_name" {                               # output: the group
  value       = aws_autoscaling_group.web.name     # the name
  description = "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <this>"   # inspect
}
