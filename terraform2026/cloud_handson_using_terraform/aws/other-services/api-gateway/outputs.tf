# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "invoke_url" {                             # output: the public URL
  value       = "https://${aws_api_gateway_rest_api.echo.id}.execute-api.us-east-1.amazonaws.com/prod/ping"   # stage URL + path
  description = "curl <this>"                      # try it
}
