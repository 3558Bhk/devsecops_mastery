# AWS 7 — Load Balancing & Auto Scaling

> **⏱️ Time to complete: ~75 min** (read + wire ALB → target group → ASG)

## 7.1 The Stack: ALB → Target Group → ASG

```
Internet → ALB (L7) → Target Group (health checks) → ASG (N EC2)
```

```hcl
# Launch template (the instance blueprint) — see EC2 chapter
resource "aws_launch_template" "web" {      # a launch template
  name_prefix   = "${local.name_prefix}-web-"   # name prefix
  image_id      = data.aws_ami.ubuntu.id   # the AMI
  instance_type = var.instance_type        # the type
  vpc_security_group_ids = [aws_security_group.web.id]   # the SGs
  iam_instance_profile   = aws_iam_instance_profile.ec2.name   # the instance profile
  user_data = base64encode(templatefile("${path.module}/user_data.sh.tmpl", {}))   # bootstrap
  metadata_options { http_tokens = "required" }   # IMDSv2
  block_device_mappings {                   # the root block device
    device_name = "/dev/xvda"                # the root device
    ebs { volume_size = 20; volume_type = "gp3"; encrypted = true }   # 20 GB encrypted gp3
  }
  tag_specifications { resource_type = "instance"; tags = { Name = "${local.name_prefix}-web" } }   # instance tags
}

# Target group (the health-checked pool)
resource "aws_lb_target_group" "web" {      # a target group
  name        = "${local.name_prefix}-web"  # the name
  port        = 80                          # the target port
  protocol    = "HTTP"                      # the protocol
  vpc_id      = aws_vpc.main.id             # the VPC
  target_type = "instance"            # or "ip" (for ECS/containers)

  health_check {                           # the health check
    healthy_threshold   = 2                # 2 successes = healthy
    unhealthy_threshold = 3                # 3 failures = unhealthy
    timeout             = 5                # per-probe timeout (s)
    interval            = 30               # probe every 30 s
    path                = "/healthz"       # the path to probe
    matcher             = "200"            # expect 200
  }

  deregistration_delay = 30   # drain in-flight requests on removal
  stickiness {                  # session stickiness
    type = "lb_cookie"
    enabled = true
  }

  tags = { Name = "${local.name_prefix}-web-tg" }
}

# The ALB itself
resource "aws_lb" "web" {                # an Application Load Balancer
  name               = "${local.name_prefix}-web"   # the name
  load_balancer_type = "application"     # L7
  subnets            = aws_subnet.public[*].id      # public subnets
  security_groups    = [aws_security_group.alb.id]  # the ALB SG
  internal           = false              # internet-facing

  enable_deletion_protection = (var.environment == "prod")   # protect (prod)

  tags = { Name = "${local.name_prefix}-web-alb" }
}

# Listener (port → action)
resource "aws_lb_listener" "http" {      # a listener
  load_balancer_arn = aws_lb.web.arn     # the ALB
  port              = 80                 # listen on 80
  protocol          = "HTTP"             # HTTP

  default_action {                       # the default action
    type             = "forward"          # forward
    target_group_arn = aws_lb_target_group.web.arn   # to this target group
  }
}

# Register the ASG (or instances) with the target group
resource "aws_autoscaling_group" "web" {   # the autoscaling group
  name                = "${local.name_prefix}-web"   # the ASG name
  launch_template {                       # which launch template to use
    id      = aws_launch_template.web.id   # the template
    version = "$Latest"                    # always the latest version
  }

  min_size         = 2                    # minimum instances
  max_size         = 6                    # maximum instances
  desired_capacity = 2                    # starting capacity

  vpc_zone_identifier = aws_subnet.private[*].id   # the private subnets (one per AZ)
  # (or availability_zones = local.azs)

  health_check_type         = "ELB"        # use ALB health checks (better than EC2)
  health_check_grace_period = 300          # grace period (s)

  # Replace instances on launch template change
  instance_refresh {                       # rolling refresh
    strategy = "Rolling"                   # rolling strategy
    preferences {
      min_healthy_percentage = 50          # keep at least 50% healthy
    }
  }

  # Tags applied to the launched instances
  tags = [
    { key = "Name"; value = "${local.name_prefix}-web"; propagate_at_launch = true },   # Name tag
    { key = "managed-by"; value = "asg"; propagate_at_launch = true },   # managed-by tag
  ]

  # Termination: spread across AZs
  termination_policies = ["OldestInstance"]   # terminate the oldest first

  # (optional) replace oldest on update
  # force_delete = true   # dev only
}

resource "aws_lb_target_group_attachment" "web" {   # attach a target to the target group
  target_group_arn = aws_lb_target_group.web.arn   # the target group
  # attach ALL ASG instances automatically via the ASG reference
  target_id = aws_autoscaling_group.web.id   # the target (the ASG)
  port      = 80                             # the port
}
```

> For an **ASG**, you often don't need a per-instance `aws_lb_target_group_attachment` — the ASG + target group wire up together, or you attach the ASG as a single target. Explicit per-instance attachments are for static `aws_instance`s.

## 7.2 Listener Rules (routing by path/host)

```hcl
# API path → different target group
resource "aws_lb_listener_rule" "api" {     # a listener rule
  listener_arn = aws_lb_listener.http.arn   # the listener

  action {                                   # what to do
    type             = "forward"             # forward
    target_group_arn = aws_lb_target_group.api.arn   # to the api target group
  }

  condition {                                # when to apply
    path_patterns {
      values = ["/api/*"]                    # the /api/* path
    }
  }
}

# Redirect everything else to HTTPS
resource "aws_lb_listener" "https" {        # the HTTPS listener
  load_balancer_arn = aws_lb.web.arn        # the ALB
  port              = 443                   # listen on 443
  protocol          = "HTTPS"               # HTTPS
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"   # a strong TLS policy
  certificates      = [{ certificate_arn = aws_acm_certificate.wildcard.arn }]   # the ACM cert

  default_action {                           # the default action
    type             = "forward"             # forward
    target_group_arn = aws_lb_target_group.web.arn   # to the web target group
  }
}

resource "aws_lb_listener_rule" "redirect" {   # a redirect rule
  listener_arn = aws_lb_listener.http.arn   # the HTTP listener
  action {                                   # the action
    type = "redirect"                        # redirect
    redirect {                               # the redirect target
      port        = "443"                    # to port 443
      protocol    = "HTTPS"                  # over HTTPS
      code        = "301"                    # permanent
    }
  }
}
```

## 7.3 Scaling Policies

```hcl
# Target tracking (CPU < 60%) — the common one
resource "aws_autoscaling_policy" "cpu" {     # a scaling policy
  name                   = "cpu-target"       # the policy name
  autoscaling_group_name = aws_autoscaling_group.web.name   # the ASG
  policy_type            = "TargetTrackingScaling"   # target tracking

  target_tracking_configuration {             # the target settings
    predefined_metric_type = "ASGAverageCPUUtilization"   # the metric
    target_value           = 60               # keep CPU around 60%
  }
}

# Scale out at 9am, in at 7pm (business hours)
resource "aws_autoscaling_schedule" "mornings" {   # a scheduled scale
  scheduled_action_name = "scale-up-9am"   # the action name
  autoscaling_group_name = aws_autoscaling_group.web.name   # the ASG
  min_size         = 4                    # set min
  desired_capacity = 4                    # set desired
  max_size         = 8                    # set max
  time             = "9:00"               # the time
  timezone         = "Asia/Kolkata"       # the timezone
  recurrence       = "0 9 * * ?"   # cron-like (AWS format)
}

# Predictive scaling (forecast-based) — opt-in
resource "aws_autoscaling_policy" "predictive" {   # a predictive policy
  name                   = "predictive"   # the name
  autoscaling_group_name = aws_autoscaling_group.web.name   # the ASG
  policy_type            = "PredictiveScaling"   # predictive
  predictive_scaling_configuration {     # the predictive settings
    prediction_type = "ForecastAndScale" # forecast + scale
  }
}
```

Policy types: **TargetTracking** (keep a metric at a value), **StepScaling** (bands), **Simple** (one condition), **Predictive**.

## 7.4 ALB vs NLB vs GWLB

| | **ALB** (L7) | **NLB** (L4) | **GWLB** (appliance) |
|---|---|---|---|
| Layer | HTTP/HTTPS | TCP/UDP | TCP (appliance load balancer) |
| Path/host routing | ✅ | ❌ |  |
| Static IP / anycast | ❌ (EIP per AZ) | ✅ (static, anycast) | ✅ |
| TLS termination | ✅ (ACM) | Passthrough (or TLS) | n/a |
| Use | Web/API | High-perf, fixed IP, non-HTTP | Firewall/IDS appliances |

- **ALB** = default for web/app. **NLB** = when you need a **static IP**, ultra-low latency, or TCP/UDP. **GWLB** = chaining security appliances.

## 7.5 Getting It Right / Gotchas

- **Target group `health_check`** path must actually exist and return `matcher` (e.g. `/healthz` → 200).
- **`health_check_type = "ELB"`** on the ASG → scaling uses the ALB's view (smarter).
- **`instance_refresh`** → rolling replace when the launch template changes (zero-downtime updates).
- **`deregistration_delay`** → in-flight request drain.
- **`vpc_zone_identifier`** = private subnets across AZs (one per AZ for spread).
- **ALB needs to be in public subnets** (if internet-facing) + an **ACM cert** in the **same region** (us-east-1 for CloudFront).
- **`enable_deletion_protection`** on the ALB in prod.
- **`stickiness`** only when the app is stateful (prefer stateless).
- **Cost**: ALB charges per LCUs + processed bytes; NAT GW per GB — big on high-traffic.
- **Min ≥ 2** (ideally one per AZ) for HA.

## 7.6 Interview Quick Facts

- **ALB (L7)** path/host routing + TLS; **NLB (L4)** static IP + TCP/UDP; **GWLB** appliances.
- **Target group** = the health-checked pool the LB forwards to.
- **ASG** maintains N healthy instances; **launch template** = the blueprint.
- **Target tracking** keeps a metric (CPU) at a target value.
- **`instance_refresh`** = rolling replace on template change.
- **`health_check_type = "ELB"`** makes the ASG trust the LB.
- **ALB** in public subnets + **ACM** cert (region-specific; us-east-1 for CFN).
