# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "function_arn" {                           # output: the function
  value       = aws_lambda_function.hello.arn        # the ARN
  description = "aws lambda invoke --function-name lab-hello /tmp/out.json"   # try it
}

output "test_invoke" {                            # output: an invoke with an event
  value       = "aws lambda invoke --function-name lab-hello --payload '{\"name\":\"terraform\"}' /tmp/out.json"   # the full command
  description = "then: cat /tmp/out.json"            # the response
}
