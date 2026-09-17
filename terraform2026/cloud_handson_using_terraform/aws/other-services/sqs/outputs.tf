# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "queue_url" {                              # output: the queue
  value       = aws_sqs_queue.work.url               # the URL
  description = "aws sqs send-message --queue-url <this> --message-body hi"   # send a message
}

output "dlq_url" {                                # output: the DLQ
  value       = aws_sqs_queue.dlq.url                # the URL
  description = "check here when a consumer keeps failing"                  # the poison parking lot
}
