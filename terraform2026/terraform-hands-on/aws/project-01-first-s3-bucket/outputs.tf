output "bucket_name" {                           # output block: show this value after apply
  value       = aws_s3_bucket.hello.id           # the value to show = the bucket's name
  description = "The name of your first bucket"  # a human hint printed next to the value
}

output "bucket_arn" {                            # a second output
  value       = aws_s3_bucket.hello.arn          # the bucket's ARN (its unique AWS-wide ID)
  description = "Other AWS services reference the bucket by this ARN"   # e.g. Lambda, CloudFront
}
