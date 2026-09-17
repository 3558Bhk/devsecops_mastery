# ============================================================================
#  Route 53 — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_route53_zone" "lab" {              # the hosted zone
  name    = "lab-2026.example.com"               # the DOMAIN (use one you own for real resolution)
  comment = "managed by terraform"               # a note
  tags    = { env = "lab" }                      # a label
}

resource "aws_route53_health_check" "ip" {       # the health check (a standalone monitor)
  ip_address = "3.100.200.10"                     # the address to probe (dummy — use a real one)
  port       = 80                                 # the port
  type       = "HTTP"                             # probe with an HTTP GET
  resource_path = "/"                             # the path
  request_interval = 10                           # probe every 10s
  failure_threshold = 2                           # 2 misses = unhealthy

  # (a real example points at your load balancer's IP or an EC2 public IP)
}

resource "aws_route53_record" "www" {            # an A record: name → IP
  zone_id = aws_route53_zone.lab.id              # which zone
  name    = "www"                                # the record's name (www.lab-2026.example.com)
  type    = "A"                                  # an IPv4 address record
  ttl     = 300                                  # cache for 5 minutes
  records = ["52.0.0.100"]                        # the IP(s) (dummy — use a real one)

  # health_check_id = aws_route53_health_check.ip.id   # ← uncomment to make the record health-aware
}

resource "aws_route53_record" "api_weighted_a" { # a WEIGHTED record (canary pattern), option A
  zone_id = aws_route53_zone.lab.id              # which zone
  name    = "api"                                # api.lab-2026.example.com
  type    = "A"                                  # IPv4
  ttl     = 60                                   # short TTL (canaries flip fast)
  records = ["52.0.0.101"]                        # the "current" backend

  set_identifier          = "api-90"             # weighted records share a name+type and need an id
  weighted_routing_policy {                       # the weighted routing policy
    weight = 90                                   # 90% of traffic here
  }
}

resource "aws_route53_record" "api_weighted_b" { # the same name, the "new" backend at 10% (the canary)
  zone_id = aws_route53_zone.lab.id              # which zone
  name    = "api"                                # SAME name as above (that's how weighted works)
  type    = "A"                                  # IPv4
  ttl     = 60                                   # same TTL
  records = ["52.0.0.102"]                        # the canary backend

  set_identifier = "api-10"                      # the other id
  weighted_routing_policy {                       # the weighted routing policy
    weight = 10                                   # 10% of traffic (the canary slice)
  }
}
