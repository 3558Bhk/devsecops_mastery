# ============================================================================
#  Capstone 5 — Multi-Cloud Global Web (AWS + Azure, one DNS, health failover)
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_vpc" "main" {                      # the VPC
  cidr_block = "10.50.0.0/16"                    # the address space
}

resource "aws_subnet" "a" {                      # subnet A
  vpc_id            = aws_vpc.main.id           # which VPC
  cidr_block        = "10.50.1.0/24"            # the slice
  availability_zone = "us-east-1a"              # AZ a
}

resource "aws_subnet" "b" {                      # subnet B
  vpc_id            = aws_vpc.main.id           # which VPC
  cidr_block        = "10.50.2.0/24"            # the slice
  availability_zone = "us-east-1b"              # AZ b
}

resource "aws_internet_gateway" "main" {         # the IGW
  vpc_id = aws_vpc.main.id                       # which VPC
}

resource "aws_route_table" "public" {            # the public route table
  vpc_id = aws_vpc.main.id                       # which VPC
  route {                                         # the default route
    cidr_block = "0.0.0.0/0"                      # anywhere
    gateway_id = aws_internet_gateway.main.id     # via the IGW
  }
}

resource "aws_route_table_association" "a" {     # associate A
  subnet_id      = aws_subnet.a.id              # which subnet
  route_table_id = aws_route_table.public.id     # which table
}

resource "aws_route_table_association" "b" {     # associate B
  subnet_id      = aws_subnet.b.id              # which subnet
  route_table_id = aws_route_table.public.id     # which table
}

resource "aws_security_group" "web" {            # the web SG
  name   = "mc-web-sg"                           # the group's name
  vpc_id = aws_vpc.main.id                       # which VPC

  ingress {                                      # HTTP from anywhere
    description = "HTTP"                         # a label
    from_port   = 80                           # the port
    to_port     = 80                           # the port
    protocol    = "tcp"                        # the protocol
    cidr_blocks = ["0.0.0.0/0"]                # anywhere
  }
  egress {                                       # allow out
    from_port   = 0                              # all ports
    to_port     = 0                              # all ports
    protocol    = "-1"                           # all protocols
    cidr_blocks = ["0.0.0.0/0"]                # anywhere
  }
}

data "aws_ami" "al2023" {                         # the base AMI
  most_recent = true                               # the latest
  owners      = ["amazon"]                         # from Amazon
  filter {
    name   = "name"                               # by name
    values = ["al2023-ami-2023*-x86_64"]          # the pattern
  }
}

resource "aws_instance" "web" {                   # the EC2 web tier
  ami                    = data.aws_ami.al2023.id # the AMI
  instance_type          = "t4g.micro"            # the size (free tier)
  subnet_id              = aws_subnet.a.id        # which subnet
  vpc_security_group_ids = [aws_security_group.web.id]   # the firewall

  # the bootstrap script
user_data = <<-EOF
    #!/bin/bash
    dnf install -y httpd
    systemctl enable --now httpd
    echo "Hello from AWS (us-east-1)" > /var/www/html/index.html
    echo "healthy" > /var/www/html/health
  EOF
}

resource "aws_lb" "web" {                         # the ALB
  name               = "mc-alb"                   # the LB's name
  internal           = false                      # public
  load_balancer_type = "application"              # Layer 7
  security_groups    = [aws_security_group.alb.id]   # the ALB's SG
  subnets            = [aws_subnet.a.id, aws_subnet.b.id]   # the subnets
}

resource "aws_security_group" "alb" {            # the ALB's SG
  name   = "mc-alb-sg"                            # the group's name
  vpc_id = aws_vpc.main.id                       # which VPC
  ingress {
    description = "HTTP"                         # a label
    from_port   = 80                           # the port
    to_port     = 80                           # the port
    protocol    = "tcp"                        # the protocol
    cidr_blocks = ["0.0.0.0/0"]                # anywhere
  }
  egress {
    from_port   = 0                              # all ports
    to_port     = 0                              # all ports
    protocol    = "-1"                           # all protocols
    cidr_blocks = ["0.0.0.0/0"]                # anywhere
  }
}

resource "aws_lb_target_group" "web" {           # the target group
  name              = "mc-tg"                    # the TG's name
  port              = 80                         # the port
  protocol          = "HTTP"                     # the protocol
  vpc_id            = aws_vpc.main.id            # which VPC

  health_check {                                 # the health check
    path                = "/health"              # the path
    port                = "traffic-port"         # the instance's port
    healthy_threshold   = 2                      # 2 good = healthy
    unhealthy_threshold = 2                      # 2 bad = unhealthy
    timeout             = 3                      # the timeout
    interval            = 10                     # every 10s
    matcher             = "200"                  # expect 200
  }
}

resource "aws_lb_target_group_attachment" "web" {   # attach the EC2 to the TG
  target_id = aws_instance.web.id              # the instance
  target_group_arn = aws_lb_target_group.web.arn   # which TG
  port      = 80                             # the port
}

resource "aws_lb_listener" "http" {              # the listener
  load_balancer_arn = aws_lb.web.arn             # which ALB
  port              = 80                         # the port
  protocol          = "HTTP"                     # the protocol
  default_action {
    type             = "forward"                 # forward
    target_group_arn = aws_lb_target_group.web.arn   # to which TG
  }
}

resource "azurerm_resource_group" "lab" {        # the resource group
  name     = "rg-mc-web"                         # the group's name
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_service_plan" "app" {          # the plan
  name                = "asp-mc"                # the plan's name
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  os_type             = "Linux"                 # the OS type
  sku_name            = "F1"                    # the SKU (the cheapest dedicated)
}

resource "azurerm_linux_web_app" "app" {         # the App Service
  name                = "webapp-mc"             # the app's name (globally unique)
  location            = azurerm_resource_group.lab.location   # region
  resource_group_name = azurerm_resource_group.lab.name       # which RG
  service_plan_id     = azurerm_service_plan.app.id   # which plan
  https_only          = true                     # force HTTPS

  site_config {                                   # the site config (required in v5)
    always_on = false                             # no keep-alive
  }

  app_settings = {
    "SAMPLE" = "azure-side"                       # a sample setting
  }
}

resource "aws_route53_zone" "lab" {              # the hosted zone (CHANGE the domain)
  name = "lab-mc.example.com"                    # the domain (you must own it)
}

resource "aws_route53_health_check" "aws_side" {   # the health check on the AWS ALB
  ip_address = aws_lb.web.zone_id == "" ? "1.2.3.4" : aws_lb.web.zone_id   # (placeholder; see below)
  port       = 80                             # the port
  type       = "HTTP"                         # the type (HTTP)
  resource_path = "/health"                  # the path
  request_interval = 10                       # probe every 10s
  failure_threshold = 2                       # 2 fails = unhealthy

  # NOTE: for a real ALB, the health check targets the ALB's DNS name + zone id.
}

resource "aws_route53_health_check" "azure_side" {   # the health check on the App Service
  ip_address = "1.2.3.4"                     # (the App Service's IP — CHANGE)
  port       = 443                            # the port
  type       = "HTTPS"                        # the type (HTTPS)
  resource_path = "/"                        # the path
  request_interval = 10                       # probe every 10s
  failure_threshold = 2                       # 2 fails = unhealthy
}

resource "aws_route53_record" "primary" {       # the PRIMARY record (AWS)
  zone_id = aws_route53_zone.lab.zone_id         # which zone
  name    = "primary"                           # the record's name
  type    = "A"                                  # an A record

  health_check_id = aws_route53_health_check.aws_side.id   # the health check
  set_identifier = "web"                       # ties the pair together (v5: required)

  failover_routing_policy {                        # the failover policy
    type = "PRIMARY"                          # this is the PRIMARY
  }

  alias {                                        # an ALIAS to the ALB
    name    = aws_lb.web.dns_name              # the ALB's DNS name
    zone_id = aws_lb.web.zone_id               # the ALB's zone id
    evaluate_target_health = true              # reflect the ALB's health (required in v5)
  }
}

resource "aws_route53_record" "failover" {      # the FAILOVER record (Azure)
  zone_id = aws_route53_zone.lab.zone_id         # which zone
  name    = "failover"                          # the record's name
  type    = "A"                                  # an A record

  health_check_id = aws_route53_health_check.azure_side.id   # the health check
  set_identifier = "web"                       # ties the pair together (v5: required)

  failover_routing_policy {                        # the failover policy
    type = "SECONDARY"                        # this is the SECONDARY
  }

  # The App Service's IP (CHANGE to the real one)
  records = ["1.2.3.4"]                       # the IP (the App Service)
}
