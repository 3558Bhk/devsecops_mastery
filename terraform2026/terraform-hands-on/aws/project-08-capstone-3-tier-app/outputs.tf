output "alb_dns" {                                  # output: the ALB's DNS name
  value       = aws_lb.web.dns_name                  # e.g. capstone-alb-123.elb.us-east-1.amazonaws.com
  description = "The dynamic site: curl http://this" # what to test
}

output "static_url" {                               # output: the CloudFront URL
  value       = "https://${aws_cloudfront_distribution.static.domain_name}"   # e.g. https://a1b2c3.cloudfront.net
  description = "The static site: curl -s https://this" # what to test
}

output "db_endpoint" {                              # output: how to reach the database
  value       = aws_db_instance.db.endpoint          # e.g. capstone-db.xxxxxx.us-east-1.rds.amazonaws.com:5432
  description = "Connect with: psql postgresql://<user>:<pw>@<endpoint>/<db_name> (user and db are in your tfvars)"   # the connection recipe
}

output "asg_name" {                                 # output: the ASG's name
  value       = aws_autoscaling_group.web.name       # from the resource
  description = "Use it with aws autoscaling update-auto-scaling-group"   # how to scale
}
