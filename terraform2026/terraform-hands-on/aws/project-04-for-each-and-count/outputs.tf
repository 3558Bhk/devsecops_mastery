output "bucket_names" {                          # output: all buckets as a map
  value       = { for k, v in aws_s3_bucket.per_env : k => v.id }   # for-expression: key → value for each item
  description = "Each environment → its bucket name"   # { dev = "app-dev-data", ... }
}

output "worker_ips" {                            # output: all instance IPs as a list
  value       = aws_instance.workers[*].public_ip   # splat [*] = "collect this from every item"
  description = "Public IPs of every worker instance"  # e.g. ["54.1.2.3"]
}
