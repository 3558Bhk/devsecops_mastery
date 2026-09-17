output "bucket_name" {                             # output: the trigger bucket
  value       = aws_s3_bucket.events.id            # its name
  description = "Upload a file here to fire the function"   # how to test
}

output "function_name" {                           # output: the function's name
  value       = aws_lambda_function.hello.function_name   # from the resource
  description = "Used to read logs: aws logs tail /aws/lambda/<this>"   # the debug command
}

output "function_arn" {                            # output: the function's ARN
  value       = aws_lambda_function.hello.arn      # the unique ID
  description = "What the S3 notification points at"   # for reference
}
