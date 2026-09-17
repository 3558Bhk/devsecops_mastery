output "state_machine_arn" {                      # output: the machine's ARN
  value       = aws_sfn_state_machine.order_pipeline.arn   # the ARN
  description = "aws stepfunctions start-sync-execution --state-machine-arn <this> --input '{...}'"   # how to start it
}

output "state_machine_url" {                      # output: the visual workflow in the console
  value       = "https://console.aws.amazon.com/states/home#/v2/states/home"   # the states console
  description = "Open it and find your -order-pipeline machine to watch runs live"   # what to do
}

output "archive_bucket" {                         # output: where finished orders land
  value       = aws_s3_bucket.archive.id           # the bucket
  description = "aws s3 ls s3://<this>/orders/"    # check the results
}

output "large_orders_topic_arn" {                 # output: where big-order alerts go
  value       = aws_sns_topic.large_orders.arn     # the topic
  description = "Subscribe an email/phone to it to get paged"   # how to complete the loop
}
