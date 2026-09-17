# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "service_name" {                            # output: the service
  value       = aws_ecs_service.nginx.name             # the name
  description = "aws ecs describe-services --cluster lab-ecs --services nginx"   # inspect the task
}
