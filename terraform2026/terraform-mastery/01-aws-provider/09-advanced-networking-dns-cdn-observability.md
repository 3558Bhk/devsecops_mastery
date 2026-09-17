# AWS 9 — DNS (Route 53), CDN (CloudFront), WAF & Observability

> **⏱️ Time to complete: ~75 min** (read + set up a CloudFront distribution + a metric alarm)

## 9.1 Route 53 — DNS

```hcl
data "aws_route53_zone" "main" {              # read an existing hosted zone
  name = "example.com"        # existing zone
  # private_zone = true       # (or a VPC-internal private zone)
}

# A record pointing at the ALB (alias = no extra cost, follows ALB IPs)
resource "aws_route53_record" "web" {        # a Route 53 record
  zone_id = data.aws_route53_zone.main.id   # the zone
  name    = "www.example.com"               # the record name
  type    = "A"                             # an A record

  alias {                                    # an alias (points at an AWS resource)
    name    = aws_lb.web.dns_name            # the ALB's DNS name
    zone_id = aws_lb.web.zone_id             # the ALB's zone id
    evaluate_target_health = true            # use the ALB's health
  }
}

# CNAME (for subdomains of another zone) or plain A with TTL
resource "aws_route53_record" "api" {        # a CNAME record
  zone_id = data.aws_route53_zone.main.id   # the zone
  name    = "api.example.com"               # the record name
  type    = "CNAME"                          # a CNAME record
  ttl     = 300                              # time-to-live (s)
  records = [aws_lb.api.dns_name]            # the target
}

# Multi-value (round-robin) for static IPs
resource "aws_route53_record" "rr" {         # a multi-value A record
  zone_id = data.aws_route53_zone.main.id   # the zone
  name    = "pool.example.com"              # the record name
  type    = "A"                             # an A record
  ttl     = 60                               # TTL (s)
  records = ["1.2.3.4", "5.6.7.8"]           # multiple IPs (round-robin)
}
```

**Routing policies:**

| Policy | Behavior |
|---|---|
| **Simple** (default) | Round-robin among records |
| **Failover** | Primary + secondary (needs a **health check**) |
| **Latency-based** | Serve from the region with lowest latency to the user |
| **Weighted** | Split traffic by percentage (canary!) |
| **Geolocation** | By user's country/region |
| **Multivalue answers** | Up to 8 healthy IPs (health-checked) |

**Health checks** (drive failover/multivalue):

```hcl
resource "aws_route53_health_check" "alb" {   # a health check
  ip_address        = "1.2.3.4"               # the IP to probe
  endpoint_type     = "IP"                    # probe an IP (or "ALB" with target_load_balancer_id)
  health_check_type = "HTTP"                  # an HTTP check
  resource_path     = "/healthz"              # the path
  port              = 443                     # the port
  request_interval  = 10                      # probe every 10 s
  failure_threshold = 2                       # 2 failures = unhealthy

  # or endpoint_type = "ALB" with target_load_balancer_id
  # or a "calculator" (synthetic) check:
  # health_check_type = "CALCULATOR" (measurement-based)
}

resource "aws_route53_record" "failover_primary" {   # a failover (primary) record
  zone_id = data.aws_route53_zone.main.id   # the zone
  name    = "app.example.com"               # the record name
  type    = "A"                             # an A record
  set_identifier = "primary"                # the failover set id
  health_check_id = aws_route53_health_check.alb.id   # the health check
  failover_routing_policy {                  # the failover policy
    type = "PRIMARY"                        # this is the primary
  }
  alias {                                    # alias to the ALB
    name    = aws_lb.web.dns_name            # the ALB
    zone_id = aws_lb.web.zone_id             # its zone
  }
}
```

**Private Zone** = internal DNS (e.g. `internal.example.com` resolvable only inside the VPC) — great for S3 buckets, RDS, service discovery.

## 9.2 CloudFront — CDN (the global edge)

```hcl
# Cert for CloudFront MUST be in us-east-1
provider "aws" {                             # an aliased provider
  alias  = "us_east"                         # alias name
  region = "us-east-1"                       # us-east-1 (required for CFN certs)
}

resource "aws_acm_certificate" "wildcard" {   # an ACM certificate
  provider          = aws.us_east            # in us-east-1
  domain_name       = "*.example.com"        # the wildcard domain
  validation_method = "DNS"                  # validate via DNS

  lifecycle {                                 # lifecycle
    create_before_destroy = true             # create the new cert before destroying the old
  }
}

data "aws_acm_certificate_validation" "wildcard" {   # block until the cert is validated
  provider = aws.us_east                      # us-east-1
  certificate_arn = aws_acm_certificate.wildcard.arn   # the cert
}

# S3 → CloudFront via Origin Access Control (private bucket, no public access)
resource "aws_cloudfront_origin_access_control" "s3" {   # an OAC
  name                              = "${local.name_prefix}-s3-oac"   # the name
  origin_access_control_origin_type = "s3"                     # for an S3 origin
  signing_behavior                  = "always"                 # always sign requests
  signing_protocol                  = "sigv4"                  # SigV4
}

resource "aws_cloudfront_distribution" "site" {   # the CloudFront distribution
  # (depends on ACM validation)
  depends_on = [data.aws_acm_certificate_validation.wildcard]   # wait for the cert

  aliases          = ["www.example.com", "example.com"]   # the custom domain(s)
  default_root_object = "index.html"                      # the default object
  price_class      = "PriceClass_100"     # all edges (or _200/_100)

  origin {                                   # the origin
    domain_name              = aws_s3_bucket.app.bucket_regional_domain_name   # the S3 bucket
    origin_id                = "s3-app"     # the origin id
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id   # the OAC
  }

  default_cache_behavior {                   # the default cache behavior
    target_origin_id       = "s3-app"       # which origin
    viewer_protocol_policy = "redirect-to-https"   # force HTTPS
    allowed_methods        = ["GET", "HEAD"]   # allowed methods
    cached_methods         = ["GET", "HEAD"]   # cached methods
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"   # Managed-CachingOptimized
    # or: min_ttl=0, default_ttl=3600, max_ttl=86400 + forwarded_values
  }

  viewer_certificate {                       # the viewer certificate
    acm_certificate_arn      = aws_acm_certificate.wildcard.arn   # the ACM cert
    ssl_support_method       = "sni-only"   # SNI-only
    minimum_protocol_version = "TLSv1.2_2021"   # minimum TLS
  }

  restrictions {                             # geo restrictions
    geo_restriction {
      restriction_type = "none"              # no restrictions
    }
  }

  web_acl_id = aws_wafv2_web_acl.cf.id == "" ? null : aws_wafv2_web_acl.cf.arn   # (see below)
  tags       = { Name = "${local.name_prefix}-cf" }
}
```

**CloudFront key ideas:**
- **Origins** = where content comes from (S3, ALB, custom).
- **Behaviors** = how to cache/serve (default + per-path).
- **OAC (Origin Access Control)** = private S3 access (replaces the old OAI).
- **Edge** = global PoPs; **price class** = how many edges you use.
- **Cache policies / cache keys** control what's cached.
- Certs for **custom domains** must be in **us-east-1** (or use the free `*.cloudfront.net` with the CloudFront default cert).

## 9.3 WAF v2 (web application firewall)

```hcl
resource "aws_wafv2_web_acl" "cf" {          # a WAF web ACL
  name        = "${local.name_prefix}-waf"   # the name
  scope       = "CLOUDFRONT"     # or "REGIONAL" (for ALB/API GW)
  description = "Block obvious bad actors"   # description

  default_action {                           # the default action
    allow {}                                 # allow by default
  }

  # AWS-managed rules (SQLi, XSS, bots)
  rule {                                      # a WAF rule
    name        = "aws-managed"              # the rule name
    priority    = 1                          # the priority (lower = first)
    action      { block {} }                 # block matching traffic
    statement {                               # the matching statement
      managed_rule_group_statement {          # use a managed rule group
        name        = "AWSManagedRulesCommonRuleSet"   # the common rule set
        scope_down_statement {                # narrow the scope
          not_statement {                     # EXCEPT for these
            ip_set_reference_statement {      # this IP set
              arn = aws_wafv2_ip_set.trusted.arn   # (your office IPs)
            }
          }
        }
      }
    }
    visibility_config {                       # the visibility settings
      cloudwatch_metrics_enabled = true       # emit metrics
      metric_name                = "aws-managed"   # the metric name
      sampled_requests_enabled   = true       # sample requests
    }
  }

  tags = { Name = "${local.name_prefix}-waf" }
}
```

- **Scope**: `CLOUDFRONT` (global) vs `REGIONAL` (per-region ALB/API GW).
- **Rule types**: IP sets, rate-based (DDoS), geo, sized/label, **managed rule groups** (AWS/community).
- Attach the `web_acl_id` to CloudFront / ALB / API GW.

## 9.4 Observability (CloudWatch)

```hcl
# Log group + retention
resource "aws_cloudwatch_log_group" "app" {   # a log group
  name              = "/${local.name_prefix}/app"   # the log group name
  retention_in_days = 30                        # keep 30 days
  # kms_key_id = aws_kms_key.logs.arn           # (optional) encrypt
}

# Metric alarm (CPU)
resource "aws_cloudwatch_metric_alarm" "cpu_high" {   # a metric alarm
  alarm_name          = "${local.name_prefix}-cpu-high"   # the alarm name
  namespace           = "AWS/EC2"                     # the metric namespace
  metric_name         = "CPUUtilization"              # the metric
  statistic           = "Average"                     # the statistic
  period              = 300                           # 5-minute period
  evaluation_periods  = 2                             # 2 consecutive periods
  threshold           = 80                            # the threshold
  comparison_operator = "GreaterThanThreshold"        # the comparison

  dimensions = {                                      # the metric dimensions
    AutoScalingGroupName = aws_autoscaling_group.web.name   # this ASG
  }

  alarm_actions = [aws_sns_topic.alarms.arn]         # what to do on alarm
  ok_actions    = [aws_sns_topic.alarms.arn]         # what to do when OK
}

# Composite alarm (multi-metric)
resource "aws_cloudwatch_composite_alarm" "degraded" {   # a composite alarm
  alarm_name = "${local.name_prefix}-degraded"   # the name
  alarm_rule = jsonencode({                        # the rule (ALARM_RULE_LANGUAGE)
    "Version": "2010-03-31",
    "Statement": {
      "Combinations": [                              # the combined metrics
        { "MetricId": "m1", "Expression": "SEARCH({\"AWS/EC2\",\"AutoScalingGroupName\",\"${aws_autoscaling_group.web.name}\"}, \"Average CPUUtilization\", 300)", "DataPointsToAlarm": 2, "ComparisonOperator": "GreaterThanThreshold", "Threshold": 80 },
        { "MetricId": "m2", "Expression": "SEARCH({\"AWS/ApplicationLB\",\"LoadBalancer\",\"${aws_lb.web.name}\"}, \"Average HTTPCode_ELB_5XX_Count\", 300)", "DataPointsToAlarm": 2, "ComparisonOperator": "GreaterThanThreshold", "Threshold": 10 }
      ],
      "Count": 1,                                     # alarm when at least 1 matches
      "Language": "ALARM_RULE_LANGUAGE_VERSION_1_0"
    }
  })
}

# Dashboard
resource "aws_cloudwatch_dashboard" "app" {   # a dashboard
  dashboard_body = jsonencode({                # the dashboard JSON
    widgets = [{                                # one widget
      type   = "metric"                         # a metric widget
      width  = 24                               # the width
      height = 6                                # the height
      x = 0; y = 0                              # the position
      properties = {                             # the widget properties
        metrics = [["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.web.name]]   # the metric
        view    = "timeSeries"                  # the view
      }
    }]
  })
}
```

**CloudWatch building blocks:**
- **Metrics** (numeric, e.g. CPUUtilization, RequestCount) → **Dashboards**, **Alarms**.
- **Logs** (`aws_cloudwatch_log_group`) → **Insights** (query), **Filters**.
- **Synthetics** (Canaries) → end-to-end synthetic tests.
- **Alarm actions** → SNS / SQS / Lambda / ASG (auto-scale) / SSM (auto-repair).
- **Composite alarms** = boolean logic across metrics.

## 9.5 Getting It Right / Gotchas

- **Alias vs CNAME**: use **alias** for ELB/R3/CloudFront (no extra charge, follows changing IPs). CNAME is for external names.
- **ACM for CloudFront = us-east-1** (region-specific).
- **OAC** (not the legacy OAI) for private S3.
- **Failover routing** needs **health checks** (or it won't fail over).
- **WAF scope** must match where you attach it (CLOUDFRONT vs REGIONAL).
- **CloudWatch alarm `dimensions`** must match the metric's actual dimensions (or it sees no data).
- **Log retention**: set it (default = infinite → cost).
- **`price_class`** = edge coverage vs cost.

## 9.6 Interview Quick Facts

- **Route 53** = DNS + health checks + routing policies (failover, latency, weighted, geo).
- **Alias** = free, follows target (ELB/CFN); **CNAME** = external names.
- **Failover** needs **health checks**.
- **CloudFront** = global CDN; **OAC** for private S3; certs in **us-east-1**.
- **WAF v2** = web firewall; **managed rule groups**; CLOUDFRONT vs REGIONAL scope.
- **CloudWatch** = metrics + logs + alarms + dashboards; **composite** = multi-metric logic.
- **Synthetics** = canaries (synthetic end-to-end tests).
