output "stream_arn" {                             # output: the Kinesis stream
  value       = aws_kinesis_stream.clicks.arn      # the ARN
  description = "push events: aws kinesis put-record --stream-name <last part>"   # how to generate traffic
}

output "stats_bucket" {                           # output: where the per-minute stats land
  value       = aws_s3_bucket.stats.id             # the bucket
  description = "aws s3 ls s3://<this>/minute/"    # the aggregates appear here
}

output "alerts_topic_arn" {                       # output: the fan-out topic
  value       = aws_sns_topic.alerts.arn           # the topic
  description = "Subscribe email/Slack/SQS; fires on every new minute file"   # complete the loop
}

output "region" {                                 # output: the region (for your aws CLI commands)
  value       = var.region                         # from the variable
  description = "pass to --region"                 # handy
}
