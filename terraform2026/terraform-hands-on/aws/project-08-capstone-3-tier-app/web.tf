# ── WEB TIER: ALB → target group → auto scaling group ─────────────────────────

resource "aws_launch_template" "web" {              # the "recipe" describing how each instance is built
  name_prefix          = "${var.project}-web-"      # AWS appends a number to make it unique
  image_id             = data.aws_ami.al2023.id     # boot from this image
  instance_type        = var.instance_type          # size from the variable
  vpc_security_group_ids = [aws_security_group.web.id]   # apply this firewall to every instance

  # runs once at first boot (bash heredoc — no comment allowed after the EOF marker!)
  user_data = <<-EOF
    #!/bin/bash
    yum update -y && yum install -y httpd          # install Apache
    systemctl enable --now httpd                   # start it
    echo "Hello from the Terraform capstone! ($HOSTNAME)" > /var/www/html/index.html   # page shows WHICH server answered
  EOF
}

resource "aws_lb_target_group" "web" {              # the pool of instances the ALB can send traffic to
  name      = "${var.project}-web"                  # unique name
  port      = 80                                    # what port to hit on each instance
  protocol  = "HTTP"                                # speak HTTP
  vpc_id    = module.vpc.vpc_id                     # inside the module's VPC
  target_type = "instance"                          # the targets are EC2 instances

  health_check {                                    # how the ALB checks instances are alive
    healthy_threshold   = 2                         # 2 OK checks → healthy
    unhealthy_threshold = 2                         # 2 failed checks → unhealthy
    timeout             = 5                         # seconds to wait per check
    interval            = 10                        # seconds between checks
    path                = "/"                       # check this URL
    matcher             = "200"                     # this HTTP code = healthy
  }
}

resource "aws_lb" "web" {                           # the Application Load Balancer itself
  name               = "${var.project}-alb"         # unique name
  load_balancer_type = "application"                # L7 (HTTP) load balancer
  subnets            = module.vpc.subnet_ids        # one subnet per AZ (the module gives us two)
}

resource "aws_lb_listener" "web" {                  # the door: "HTTP on port 80 → forward to the target group"
  load_balancer_arn = aws_lb.web.arn                # which ALB
  port              = 80                            # listen on 80
  protocol          = "HTTP"                        # speak HTTP

  default_action {                                   # what to do with every request
    type             = "forward"                     # forward (not redirect/fix-response)
    target_group_arn = aws_lb_target_group.web.arn   # to this target group
  }
}

resource "aws_autoscaling_group" "web" {            # the ASG: keeps N healthy instances running
  name     = "${var.project}-web-asg"               # unique name
  min_size = 1                                      # never fewer than 1 instance
  max_size = 2                                      # never more than 2 (lab: keep it cheap)

  launch_template {                                  # which recipe to build instances from
    id      = aws_launch_template.web.id            # the template above
    version = "$Latest"                             # always the newest version
  }

  vpc_zone_identifier = module.vpc.subnet_ids       # where to launch (both subnets)
  target_group_arns   = [aws_lb_target_group.web.arn]   # auto-register instances in the target group

  tag {                                              # a tag applied to every instance
    key                 = "Name"                    # the tag key
    value               = "${var.project}-web"      # the tag value
    propagate_at_launch = true                      # copy the tag onto the instances themselves
  }
}
