output "bucket_name" {                           # output: the bucket's name
  value       = aws_s3_bucket.app.id             # the value to show
  description = "Bucket name, e.g. hello-dev-data"   # shown next to the value
}

output "bucket_arn" {                            # output: the bucket's ARN
  value       = aws_s3_bucket.app.arn            # the unique AWS-wide identifier
  description = "What other services use to reference this bucket"   # Lambda, CloudFront, etc.
}

output "environment" {                           # output: echo back the input you set
  value       = var.environment                  # straight from the variable
  description = "The environment this build targets"   # handy sanity check after apply
}
