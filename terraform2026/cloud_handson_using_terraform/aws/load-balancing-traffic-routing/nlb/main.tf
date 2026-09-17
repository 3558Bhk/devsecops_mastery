# ============================================================================
#  NLB (Network Load Balancer) — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_vpc" "main" {                      # the VPC
  cidr_block = "10.0.0.0/16"                     # the address space
  tags       = { Name = "nlb-lab" }              # a label
}

resource "aws_subnet" "a" {                      # public subnet A
  vpc_id            = aws_vpc.main.id            # which VPC
  cidr_block        = "10.0.1.0/24"              # inside the VPC
  availability_zone = "us-east-1a"               # which AZ
}

resource "aws_subnet" "b" {                      # public subnet B
  vpc_id            = aws_vpc.main.id            # which VPC
  cidr_block        = "10.0.2.0/24"              # inside the VPC
  availability_zone = "us-east-1b"               # which AZ
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

data "aws_ami" "al2023" {                        # data block: newest Amazon Linux 2023
  most_recent = true                             # newest
  owners      = ["amazon"]                       # official only
  filter {
    name   = "name"                                 # filter field
    values = ["al2023-ami-2023*-x86_64"]            # the pattern
  }
}

resource "aws_security_group" "web" {            # the backend's firewall
  name   = "web-sg"                              # the group's name
  vpc_id = aws_vpc.main.id                       # which VPC

  ingress {                                       # allow TCP 80 from anywhere (lab)
    description = "TCP 80"                       # a label
    from_port   = 80                             # the port
    to_port     = 80                             # the same
    protocol    = "tcp"                          # the protocol
    cidr_blocks = ["0.0.0.0/0"]                  # from anywhere
  }
}

resource "aws_instance" "web" {                  # the single backend
  ami                    = data.aws_ami.al2023.id   # the image
  instance_type          = "t4g.micro"              # smallest
  subnet_id              = aws_subnet.a.id           # in AZ a
  vpc_security_group_ids = [aws_security_group.web.id] # its firewall

  # serve something on port 80
user_data = <<-EOF
    #!/bin/bash
    yum install -y httpd
    systemctl enable --now httpd
    echo "nlb-backend" > /var/www/html/index.html
    EOF
}

resource "aws_lb_target_group" "web" {           # WHO we balance to
  name     = "web-tg"                            # the group's name
  port     = 80                                  # the port ON THE TARGET
  protocol = "TCP"                               # L4: raw TCP (NLB is protocol-agnostic)
  vpc_id   = aws_vpc.main.id                     # which VPC

  health_check {                                  # NLB's default check is a TCP connect
    enabled             = true                    # on
    protocol            = "TCP"                   # connect only (no HTTP needed)
    port                = "traffic-port"          # hit the target's own port
    healthy_threshold   = 2                       # 2 successful connects = healthy
    unhealthy_threshold = 3                       # 3 failures = unhealthy
    interval            = 10                      # every 10s
  }
}

resource "aws_lb" "web" {                        # the NLB itself
  name               = "web-nlb"                 # the balancer's name
  load_balancer_type = "network"                 # THE difference: network (L4)
  subnets            = [aws_subnet.a.id, aws_subnet.b.id]   # one per AZ

  # NLB gets a static IP per AZ (shown by aws elbv2 describe-load-balancer-attributes)
}

resource "aws_lb_listener" "tcp" {               # what to listen for
  load_balancer_arn = aws_lb.web.arn             # which NLB
  port              = 80                         # the port
  protocol          = "TCP"                      # the protocol (no content inspection)

  default_action {                                # where all traffic goes
    type             = "forward"                  # forward
    target_group_arn = aws_lb_target_group.web.arn   # to this group
  }
}
