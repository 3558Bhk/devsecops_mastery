output "asg_name" {                               # output: the ASG's name
  value       = aws_autoscaling_group.web.name     # from the resource
  description = "Use with aws autoscaling describe-auto-scaling-groups"   # how to inspect
}

output "sns_topic_arn" {                          # output: the notification topic
  value       = aws_sns_topic.alerts.arn           # the ARN
  description = "Alarms publish here; subscribe email/phone/SQS to it"   # how to extend
}

output "alarm_arn" {                              # output: the alarm's ARN
  value       = aws_cloudwatch_metric_alarm.cpu_high.arn   # the ARN
  description = "Check state: aws cloudwatch describe-alarms --alarm-names <this>"   # how to inspect (INSUFFICIENT_DATA for ~10 min is normal)
}
