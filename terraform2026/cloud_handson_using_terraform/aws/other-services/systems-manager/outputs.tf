# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "instance_id" {                            # output: the instance
  value       = aws_instance.ssm.id                   # the id
  description = "aws ssm start-session --target <this>"   # open a session
}

output "env_param" {                              # output: the parameter
  value       = aws_ssm_parameter.env.name              # the name
  description = "aws ssm get-parameter --name /lab/env"  # read it
}
