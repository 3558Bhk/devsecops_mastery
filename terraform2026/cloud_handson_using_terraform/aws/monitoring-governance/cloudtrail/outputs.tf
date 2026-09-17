# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "trail_arn" {                               # output: the trail
  value       = aws_cloudtrail.lab.arn                # the ARN
  description = "aws cloudtrail describe-trails --trail-name-list lab-trail"   # inspect
}

output "log_bucket" {                              # output: the logs
  value       = aws_s3_bucket.trail.id                  # the bucket
  description = "the JSON event files land under AWSLogs/<account>/CloudTrail/"   # where to look
}
