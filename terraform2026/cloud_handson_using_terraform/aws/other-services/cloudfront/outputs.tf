# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "domain" {                                    # output: the public URL
  value       = aws_cloudfront_distribution.web.domain_name   # e.g. d1234.cloudfront.net
  description = "https://<this> (first request may be a miss — wait for deployment ~15 min)"   # test it
}
