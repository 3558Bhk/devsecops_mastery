output "topic_arn" {                              # output: the topic to publish to
  value       = aws_sns_topic.orders.arn           # the ARN
  description = "aws sns publish --topic-arn <this> --message '{\"order_id\": \"1\"}'"   # the test command
}

output "billing_queue_url" {                      # output: the billing queue
  value       = aws_sqs_queue.billing.url          # the URL
  description = "aws sqs receive-message --queue-url <this> (peek without consuming a worker)"   # how to inspect
}

output "inventory_queue_url" {                    # output: the inventory queue
  value       = aws_sqs_queue.inventory.url        # the URL
  description = "Same command as billing_queue_url"   # how to inspect
}

output "dlq_url" {                                # output: the dead-letter queue
  value       = aws_sqs_queue.billing_dlq.url      # the URL
  description = "Check here after publishing a bad message ({} )"   # where poison messages land
}

output "billing_fn" {                             # output: the billing function name
  value       = aws_lambda_function.billing.function_name   # the name
  description = "aws logs tail /aws/lambda/<this> --since 2m"   # read its logs
}

output "inventory_fn" {                           # output: the inventory function name
  value       = aws_lambda_function.inventory.function_name   # the name
  description = "aws logs tail /aws/lambda/<this> --since 2m"   # read its logs
}
