terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }   # AWS provider, any 5.x
  }
}

provider "aws" {                                 # configure the AWS provider
  region = var.region                            # from the variable
}

data "aws_ami" "al2023" {                        # data block: find the newest Amazon Linux 2023 image
  most_recent = true                             # newest
  owners      = ["amazon"]                       # official images only
  filter {                                          # match "Amazon Linux 2023" 64-bit
    name   = "name"                                 # filter on the image name
    values = ["al2023-ami-2023*-x86_64"]            # the name pattern
  }
}

resource "aws_launch_template" "web" {           # the recipe for the ASG instances
  name_prefix   = "${var.project}-cpu-"          # unique name prefix
  image_id      = data.aws_ami.al2023.id         # boot image
  instance_type = "t4g.micro"                    # smallest instance
  # install a web server (gives the instance a job) — no trailing comment on the marker line
  user_data = <<-EOF
    #!/bin/bash
    yum update -y && yum install -y httpd
    systemctl enable --now httpd
    echo "cpu-lab" > /var/www/html/index.html
  EOF
}

resource "aws_autoscaling_group" "web" {         # the ASG: keeps the fleet at a CPU target
  name     = "${var.project}-asg"                # unique name
  min_size = 1                                   # never below 1
  max_size = 2                                   # never above 2 (cheap lab)

  launch_template {                               # which recipe
    id      = aws_launch_template.web.id         # the template above
    version = "$Latest"                          # newest version
  }
}

# THE auto-scaling brain — in the AWS provider v5 this is a SEPARATE policy resource
resource "aws_autoscaling_policy" "cpu_target" {   # the policy attached to the ASG
  name                = "${var.project}-cpu-target"   # unique policy name
  policy_type         = "TargetTrackingScaling"      # the type: target tracking
  autoscaling_group_name = aws_autoscaling_group.web.name   # which ASG it drives

  target_tracking_configuration {                # the target itself
    predefined_metric_specification {            # WHICH metric (in this provider version it's a nested block)
      predefined_metric_type = "ASGAverageCPUUtilization"   # scale on the fleet's average CPU
    }
    target_value = 40                            # keep CPU around 40% (up = scale out, down = scale in)
  }
}

resource "aws_sns_topic" "alerts" {              # the notification bus
  name = "${var.project}-alerts"                 # topic name
}

resource "aws_sns_topic_subscription" "email" {  # deliver alarms by email (only if you gave an address)
  count = var.alarm_email == "" ? 0 : 1          # 0 or 1 subscription
  topic_arn = aws_sns_topic.alerts.arn           # which topic
  protocol  = "email"                            # deliver by email
  endpoint  = var.alarm_email                    # to this address (you must confirm the email!)
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {   # the alarm: "the fleet is hot"
  alarm_name          = "${var.project}-cpu-high"    # unique name
  namespace           = "AWS/AutoScaling"            # the metric's namespace (ASG metrics live here)
  metric_name         = "GroupCPUUtilization"        # the fleet's average CPU
  statistic           = "Average"                    # average over the period
  period              = 300                          # 5-minute data points
  evaluation_periods  = 2                           # 2 consecutive bad periods (10 min) before firing
  threshold           = 50                          # fire above 50%
  comparison_operator = "GreaterThanThreshold"      # the comparison
  treat_missing_data  = "notBreaching"              # missing data = not an alarm

  dimensions = {                                    # WHICH asg's metric (alarms are per-dimension)
    AutoScalingGroupName = aws_autoscaling_group.web.name   # our ASG
  }

  alarm_actions = [aws_sns_topic.alerts.arn]        # when it fires: publish to the SNS topic
}
