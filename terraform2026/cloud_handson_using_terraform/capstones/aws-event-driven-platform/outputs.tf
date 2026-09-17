# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "api_url" {                                # output: the API
  value       = "https://${aws_api_gateway_rest_api.query.id}.execute-api.us-east-1.amazonaws.com/prod/orders"   # the URL
  description = "curl <this>  (query the orders GSI)"   # try it
}

output "upload_bucket" {                          # output: the bucket
  value       = aws_s3_bucket.uploads.id                # the name
  description = "aws s3 cp payload.json s3://<this>/uploads/"   # upload to test
}

output "dlq_url" {                                # output: the DLQ
  value       = aws_sqs_queue.dlq.url                      # the URL
  description = "the dead-letter queue (messages that failed 3×)"   # the failure sink
}
