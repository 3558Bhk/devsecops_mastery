# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "topic_arn" {                              # output: the topic
  value       = aws_sns_topic.alerts.arn              # the ARN
  description = "aws sns publish --topic-arn <this> --message hi"   # publish to it
}
