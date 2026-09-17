# ============================================================================
#  Auto Scaling — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

data "aws_ami" "al2023" {                        # data block: newest Amazon Linux 2023
  most_recent = true                             # newest
  owners      = ["amazon"]                       # official
  filter {
    name   = "name"                                 # filter field
    values = ["al2023-ami-2023*-x86_64"]            # the pattern
  }
}

resource "aws_vpc" "main" {                      # the VPC
  cidr_block = "10.0.0.0/16"                     # the space
}

resource "aws_subnet" "a" {                      # public subnet A
  vpc_id            = aws_vpc.main.id            # which VPC
  cidr_block        = "10.0.1.0/24"              # inside
  availability_zone = "us-east-1a"               # AZ a
}

resource "aws_subnet" "b" {                      # public subnet B
  vpc_id            = aws_vpc.main.id            # which VPC
  cidr_block        = "10.0.2.0/24"              # inside
  availability_zone = "us-east-1b"               # AZ b (spread across AZs)
}

resource "aws_internet_gateway" "igw" {          # the internet door
  vpc_id = aws_vpc.main.id                       # which VPC
}

resource "aws_route_table" "public" {            # the public route table
  vpc_id = aws_vpc.main.id                       # which VPC
}

resource "aws_route" "internet" {                # public → internet
  route_table_id         = aws_route_table.public.id   # which table
  destination_cidr_block = "0.0.0.0/0"             # everything
  gateway_id             = aws_internet_gateway.igw.id # out the IGW
}

resource "aws_route_table_association" "a" {     # subnet A → public table
  subnet_id      = aws_subnet.a.id              # which subnet
  route_table_id = aws_route_table.public.id    # which table
}

resource "aws_route_table_association" "b" {     # subnet B → public table
  subnet_id      = aws_subnet.b.id              # which subnet
  route_table_id = aws_route_table.public.id    # which table
}

resource "aws_security_group" "web" {            # the fleet's firewall
  name   = "asg-web"                            # the group's name
  vpc_id = aws_vpc.main.id                       # which VPC

  ingress {                                      # HTTP in from anywhere (lab)
    description = "HTTP"                        # a label
    from_port   = 80                           # the port
    to_port     = 80                           # the same
    protocol    = "tcp"                        # TCP
    cidr_blocks = ["0.0.0.0/0"]                # anywhere
  }
}

resource "aws_launch_template" "web" {           # the recipe
  name_prefix = "asg-web-"                       # unique name prefix

  image_id      = data.aws_ami.al2023.id         # the boot image
  instance_type = "t4g.micro"                    # the size
  vpc_security_group_ids = [aws_security_group.web.id]  # the firewall

  block_device_mappings {                          # the root disk
    device_name = "/dev/xvda"                       # the root device
    ebs {                                           # as an EBS volume
      volume_size = 8                               # 8 GB
      volume_type = "gp3"                           # general purpose
    }
  }

  # install a web server
user_data = <<-EOF
    #!/bin/bash
    yum install -y httpd
    systemctl enable --now httpd
    echo "asg-member" > /var/www/html/index.html
    EOF
}

resource "aws_autoscaling_group" "web" {         # the group
  name     = "asg-web"                           # the group's name
  min_size = 1                                   # never below 1
  max_size = 3                                   # never above 3
  desired_capacity = 1                           # start with 1

  vpc_zone_identifier = [aws_subnet.a.id, aws_subnet.b.id]   # which subnets to spawn in

  launch_template {                               # which recipe
    id      = aws_launch_template.web.id         # the template
    version = "$Latest"                          # the newest version
  }
}

resource "aws_autoscaling_policy" "cpu_target" {   # the policy attached to the ASG
  name                = "cpu-target"              # the policy's name
  policy_type         = "TargetTrackingScaling"   # the type: target tracking
  autoscaling_group_name = aws_autoscaling_group.web.name   # which ASG it drives

  target_tracking_configuration {                # the target itself
    predefined_metric_specification {            # WHICH metric (nested block in this provider version)
      predefined_metric_type = "ASGAverageCPUUtilization"   # the fleet's average CPU
    }
    target_value = 40                            # hold CPU around 40% (hot → scale out, cold → scale in)
  }
}
