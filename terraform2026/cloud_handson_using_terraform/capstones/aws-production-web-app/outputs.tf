# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "alb_dns" {                                # output: the ALB's DNS
  value       = aws_lb.web.dns_name                     # the name
  description = "the load balancer"                       # the entry point
}

output "domain" {                                 # output: the Route 53 record
  value       = "www.lab-example.com"                   # the record
  description = "the Route 53 alias (change the zone to a domain you own)"   # the public name
}

output "cloudfront_domain" {                      # output: the CloudFront domain
  value       = aws_cloudfront_distribution.web.domain_name   # the domain
  description = "the global edge"                           # the CDN
}
