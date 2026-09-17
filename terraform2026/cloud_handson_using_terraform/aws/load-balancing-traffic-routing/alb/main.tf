# ============================================================================
#  ALB (Application Load Balancer) — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_vpc" "main" {                      # the VPC
  cidr_block = "10.0.0.0/16"                     # the address space
  tags       = { Name = "alb-lab" }              # a label
}

resource "aws_subnet" "a" {                      # public subnet A (the ALB needs ≥2 AZs)
  vpc_id            = aws_vpc.main.id            # which VPC
  cidr_block        = "10.0.1.0/24"              # inside the VPC
  availability_zone = "us-east-1a"               # which AZ
}

resource "aws_subnet" "b" {                      # public subnet B
  vpc_id            = aws_vpc.main.id            # which VPC
  cidr_block        = "10.0.2.0/24"              # inside the VPC
  availability_zone = "us-east-1b"               # which AZ
}

resource "aws_internet_gateway" "igw" {          # the internet door (the ALB is public)
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

data "aws_ami" "al2023" {                        # data block: find the newest Amazon Linux 2023 image
  most_recent = true                             # newest
  owners      = ["amazon"]                       # official images only
  filter {
    name   = "name"                                 # filter on the image name
    values = ["al2023-ami-2023*-x86_64"]            # the name pattern
  }
}

resource "aws_security_group" "web" {            # the backends' firewall
  name   = "web-sg"                              # the group's name
  vpc_id = aws_vpc.main.id                       # which VPC

  ingress {                                       # allow HTTP in from anywhere (for the lab)
    description = "HTTP"                         # a label
    from_port   = 80                             # the web port
    to_port     = 80                             # the same
    protocol    = "tcp"                          # TCP
    cidr_blocks = ["0.0.0.0/0"]                  # from anywhere
  }
}

resource "aws_instance" "web1" {                 # backend 1
  ami                    = data.aws_ami.al2023.id   # the boot image
  instance_type          = "t4g.micro"              # the smallest instance
  subnet_id              = aws_subnet.a.id           # in AZ a
  vpc_security_group_ids = [aws_security_group.web.id] # its firewall

  # install a web server (no trailing comment on the marker)
user_data = <<-EOF
    #!/bin/bash
    yum install -y httpd
    systemctl enable --now httpd
    echo "backend-1" > /var/www/html/index.html
    EOF
}

resource "aws_instance" "web2" {                 # backend 2
  ami                    = data.aws_ami.al2023.id   # same image
  instance_type          = "t4g.micro"              # same size
  subnet_id              = aws_subnet.b.id           # in AZ b (spread!)
  vpc_security_group_ids = [aws_security_group.web.id] # same firewall

  # same script, different banner
user_data = <<-EOF
    #!/bin/bash
    yum install -y httpd
    systemctl enable --now httpd
    echo "backend-2" > /var/www/html/index.html
    EOF
}

resource "aws_lb_target_group" "web" {           # WHO we balance to (and how "healthy" is defined)
  name     = "web-tg"                            # the group's name
  port     = 80                                  # the port ON THE TARGETS
  protocol = "HTTP"                              # L7 protocol (ALB target groups are HTTP/S or TCP)
  vpc_id   = aws_vpc.main.id                     # which VPC

  health_check {                                  # what "healthy" means
    enabled             = true                    # turn it on
    protocol            = "HTTP"                  # check over HTTP
    port                = "traffic-port"          # hit the target's own port
    path                = "/"                     # the URL to request
    healthy_threshold   = 2                       # 2 good checks = healthy
    unhealthy_threshold = 3                       # 3 bad checks = unhealthy
    interval            = 10                      # check every 10s
    timeout             = 5                       # give up after 5s
  }
}

resource "aws_lb" "web" {                        # the ALB itself
  name               = "web-alb"                 # the balancer's name
  load_balancer_type = "application"             # the TYPE: application (L7) — "network" for NLB
  subnets            = [aws_subnet.a.id, aws_subnet.b.id]   # one per AZ (public subnets)
}

resource "aws_lb_listener" "http" {              # WHAT to listen for, and where to send it
  load_balancer_arn = aws_lb.web.arn             # which ALB
  port              = 80                         # the port it listens on
  protocol          = "HTTP"                     # the protocol

  default_action {                                # where normal traffic goes
    type             = "forward"                  # forward (vs redirect/fix-response)
    target_group_arn = aws_lb_target_group.web.arn   # to this target group
  }
}
