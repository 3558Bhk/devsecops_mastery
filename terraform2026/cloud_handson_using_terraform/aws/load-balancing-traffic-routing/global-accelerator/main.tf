# ============================================================================
#  Global Accelerator — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_vpc" "a" {                         # VPC in us-east-1
  provider   = aws.east                          # use the EAST provider
  cidr_block = "10.1.0.0/16"                     # the space
}

resource "aws_subnet" "a" {                      # a public subnet
  provider          = aws.east                   # EAST provider
  vpc_id            = aws_vpc.a.id               # which VPC
  cidr_block        = "10.1.1.0/24"              # inside
  availability_zone = "us-east-1a"               # the AZ
}

resource "aws_internet_gateway" "a" {            # the internet door
  provider = aws.east                            # EAST provider
  vpc_id   = aws_vpc.a.id                        # which VPC
}

resource "aws_route_table" "a" {                 # the route table
  provider = aws.east                            # EAST provider
  vpc_id   = aws_vpc.a.id                        # which VPC
}

resource "aws_route" "a" {                       # → internet
  provider             = aws.east               # EAST provider
  route_table_id       = aws_route_table.a.id   # which table
  destination_cidr_block = "0.0.0.0/0"           # everything
  gateway_id           = aws_internet_gateway.a.id   # out the IGW
}

resource "aws_route_table_association" "a" {     # subnet → table
  provider       = aws.east                     # EAST provider
  subnet_id      = aws_subnet.a.id             # which subnet
  route_table_id = aws_route_table.a.id        # which table
}

data "aws_ami" "al2023" {                        # the boot image (EAST region)
  provider    = aws.east                       # EAST provider
  most_recent = true                           # newest
  owners      = ["amazon"]                     # official
  filter {
    name   = "name"                               # filter field
    values = ["al2023-ami-2023*-x86_64"]           # the pattern
  }
}

resource "aws_instance" "web" {                  # the region-A endpoint (a web server)
  provider   = aws.east                          # EAST provider
  ami        = data.aws_ami.al2023.id            # the image
  instance_type = "t4g.micro"                    # smallest
  subnet_id  = aws_subnet.a.id                   # in the public subnet
  vpc_security_group_ids = [aws_security_group.a.id]   # its firewall

  # serve "region-a"
user_data = <<-EOF
    #!/bin/bash
    yum install -y httpd
    systemctl enable --now httpd
    echo "region-a" > /var/www/html/index.html
    EOF
}

resource "aws_security_group" "a" {              # the firewall for region A
  provider = aws.east                            # EAST provider
  name   = "ga-sg"                              # the group's name
  vpc_id = aws_vpc.a.id                         # which VPC

  ingress {                                      # HTTP from anywhere (lab)
    description = "HTTP"                        # a label
    from_port   = 80                           # the port
    to_port     = 80                           # the same
    protocol    = "tcp"                        # TCP
    cidr_blocks = ["0.0.0.0/0"]                # anywhere
  }
}

resource "aws_vpc" "b" {                         # VPC in us-west-2
  provider   = aws.west                          # WEST provider
  cidr_block = "10.2.0.0/16"                     # the space
}

resource "aws_subnet" "b" {                      # a public subnet
  provider          = aws.west                   # WEST provider
  vpc_id            = aws_vpc.b.id               # which VPC
  cidr_block        = "10.2.1.0/24"              # inside
  availability_zone = "us-west-2a"               # the AZ
}

resource "aws_internet_gateway" "b" {            # the internet door
  provider = aws.west                            # WEST provider
  vpc_id   = aws_vpc.b.id                        # which VPC
}

resource "aws_route_table" "b" {                 # the route table
  provider = aws.west                            # WEST provider
  vpc_id   = aws_vpc.b.id                        # which VPC
}

resource "aws_route" "b" {                       # → internet
  provider             = aws.west               # WEST provider
  route_table_id       = aws_route_table.b.id   # which table
  destination_cidr_block = "0.0.0.0/0"           # everything
  gateway_id           = aws_internet_gateway.b.id   # out the IGW
}

resource "aws_route_table_association" "b" {     # subnet → table
  provider       = aws.west                     # WEST provider
  subnet_id      = aws_subnet.b.id             # which subnet
  route_table_id = aws_route_table.b.id        # which table
}

data "aws_ami" "al2023_west" {                   # the boot image (WEST region)
  provider    = aws.west                        # WEST provider
  most_recent = true                            # newest
  owners      = ["amazon"]                      # official
  filter {
    name   = "name"                               # filter field
    values = ["al2023-ami-2023*-x86_64"]           # the pattern
  }
}

resource "aws_instance" "web_west" {             # the region-B endpoint
  provider   = aws.west                          # WEST provider
  ami        = data.aws_ami.al2023_west.id       # the image
  instance_type = "t4g.micro"                    # smallest
  subnet_id  = aws_subnet.b.id                   # in the public subnet
  vpc_security_group_ids = [aws_security_group.b.id]   # its firewall

  # serve "region-b"
user_data = <<-EOF
    #!/bin/bash
    yum install -y httpd
    systemctl enable --now httpd
    echo "region-b" > /var/www/html/index.html
    EOF
}

resource "aws_security_group" "b" {              # the firewall for region B
  provider = aws.west                            # WEST provider
  name   = "ga-sg"                              # the group's name
  vpc_id = aws_vpc.b.id                         # which VPC

  ingress {                                      # HTTP from anywhere (lab)
    description = "HTTP"                        # a label
    from_port   = 80                           # the port
    to_port     = 80                           # the same
    protocol    = "tcp"                        # TCP
    cidr_blocks = ["0.0.0.0/0"]                # anywhere
  }
}

resource "aws_globalaccelerator_accelerator" "lab" {   # the accelerator (the anycast IPs)
  name      = "ga-lab"                            # its name
  enabled   = true                                # turn it on immediately
  ip_address_type = "IPV4"                       # IPv4 anycast IPs
  # after apply: .ip_addresses gives you the TWO global IPs to test with
}

resource "aws_globalaccelerator_listener" "http" {     # what to listen for
  accelerator_arn = aws_globalaccelerator_accelerator.lab.arn   # which accelerator
  protocol        = "TCP"                          # the protocol (GA works at L4)

  port_range {                                      # the port range to accept
    from_port = 80                                 # from
    to_port   = 80                                 # to (HTTP)
  }
}

resource "aws_globalaccelerator_endpoint_group" "east" {   # endpoint group for region A
  listener_arn         = aws_globalaccelerator_listener.http.arn   # which listener
  endpoint_group_region = "us-east-1"             # which region this group represents
  health_check_port    = 80                       # health-check this port
  health_check_path    = "/"                      # ...on this path
  traffic_dial_percentage = 50                    # steer ~50% of traffic here

  endpoint_configuration {                          # the actual backend: the EC2's public IP
    endpoint_id = aws_instance.web.public_ip        # IP endpoint = the instance's public IP
  }
}

resource "aws_globalaccelerator_endpoint_group" "west" {   # endpoint group for region B
  listener_arn         = aws_globalaccelerator_listener.http.arn   # which listener
  endpoint_group_region = "us-west-2"             # which region
  health_check_port    = 80                       # health-check port
  health_check_path    = "/"                      # path
  traffic_dial_percentage = 50                    # the other ~50%

  endpoint_configuration {                          # region B's backend
    endpoint_id = aws_instance.web_west.public_ip   # its public IP
  }
}
