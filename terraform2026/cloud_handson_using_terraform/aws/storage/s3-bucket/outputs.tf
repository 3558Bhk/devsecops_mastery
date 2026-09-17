# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "bucket_name" {                            # output: the bucket
  value       = aws_s3_bucket.lab.id               # the name
  description = "aws s3 ls s3://<this>"            # how to look
}
