# ============================================================================
# CAPSTONE 6 — MULTI-CLOUD DISASTER RECOVERY (AWS primary → Azure warm standby)
# ----------------------------------------------------------------------------
# What this is:
#   AWS (PRIMARY):  a tiny VPC + an EC2 web tier + an RDS MySQL DB + an S3 bucket
#   Azure (STANDBY): an App Service web tier + an Azure SQL DB + a storage account
#   Route 53:       a HEALTH CHECK on the AWS primary + a record that FAILS OVER
#                   to the Azure App Service hostname when the check fails.
# The data-sync story (RDS→Azure SQL, S3→Blob) is an interview talking point —
# in real life it's a scheduled dump/ETL job (out of scope for a free lab).
# Costs: EC2 + RDS + App Service + SQL run 24/7 — DESTROY immediately after.
# ============================================================================



# ═══════════════════════ AWS — THE PRIMARY ════════════════════════════════











# ═══════════════════════ AZURE — THE WARM STANDBY ═════════════════════════







# ═══════════════════════ ROUTE 53 — THE FAILOVER ══════════════════════════

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_vpc" "primary" {                    # a tiny VPC
  cidr_block           = "172.20.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "dr-primary-vpc" }
}

resource "aws_subnet" "pub" {                     # one public subnet
  vpc_id                  = aws_vpc.primary.id
  cidr_block              = "172.20.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "main" {          # the internet egress
  vpc_id = aws_vpc.primary.id
}

resource "aws_route_table" "pub" {                # the routing table
  vpc_id = aws_vpc.primary.id
  route {                                         # the default route
    cidr_block = "0.0.0.0/0"                      # anywhere
    gateway_id = aws_internet_gateway.main.id     # via the IGW
  }
}

resource "aws_route_table_association" "pub" {    # attach subnet → table
  subnet_id      = aws_subnet.pub.id
  route_table_id = aws_route_table.pub.id
}

data "aws_ami" "al2023" {                         # the cheapest Linux AMI
  most_recent = true
  owners      = ["amazon"]
  filter {                                            # by name
    name   = "name"                                   # the attribute
    values = ["al2023-ami-2023*"]                     # the pattern
  }
  filter {                                            # by virtualization type
    name   = "virtualization-type"                    # the attribute
    values = ["hvm"]                                  # HVM
  }
}

resource "aws_instance" "web" {                   # the PRIMARY web server
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.pub.id
  vpc_security_group_ids = [aws_security_group.web.id]
  user_data = <<-EOF
    #!/bin/bash
    yum install -y httpd
    systemctl enable --now httpd
    echo "AWS PRIMARY — ${replace(aws_route53_record.failover.name, ".${aws_route53_zone.lab.name}", "")}" > /var/www/html/index.html
  EOF
}

resource "aws_security_group" "web" {             # the SG (HTTP in)
  name   = "dr-web-sg"
  vpc_id = aws_vpc.primary.id
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    cidr_blocks     = ["0.0.0.0/0"]
    description     = "HTTP"
  }
  egress {                                        # out everything
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "rds" {            # the DB subnet group (RDS needs one)
  name       = "dr-rds-subnets"
  subnet_ids = [aws_subnet.pub.id]
}

resource "aws_db_instance" "orders" {             # the PRIMARY database (MySQL)
  identifier        = "dr-orders"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  db_name           = "orders"
  username          = "admin"
  password          = "Lab@Pass123"               # ⚠️ DUMMY
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  skip_final_snapshot    = true                    # destroy without a $ snapshot
  publicly_accessible    = false
}

resource "aws_s3_bucket" "static" {               # the PRIMARY static content
  bucket = "dr-lab-static"                        # ⚠️ DUMMY — must be globally unique
}

resource "azurerm_resource_group" "dr" {          # the DR group
  name     = "dr-standby-rg"
  location = var.region      # <- set in variables.tf (the region everything is built in)
}

resource "azurerm_service_plan" "standby" {       # the App Service plan
  name                = "asp-dr"
  resource_group_name = azurerm_resource_group.dr.name
  location            = azurerm_resource_group.dr.location
  os_type             = "Linux"
  sku_name            = "B1"
}

resource "azurerm_linux_web_app" "standby" {      # the STANDBY web app
  name                = "app-dr-standby"
  resource_group_name = azurerm_resource_group.dr.name
  service_plan_id     = azurerm_service_plan.standby.id
  location            = azurerm_resource_group.dr.location
  https_only          = true
  site_config {                                   # the site config (required in v5)
    always_on = false
  }
}

resource "azurerm_mssql_server" "standby" {       # the STANDBY SQL server
  name                         = "dr-sql-standby"
  resource_group_name          = azurerm_resource_group.dr.name
  location                     = azurerm_resource_group.dr.location
  version                      = "12.0"
  administrator_login          = "sqladmin"
  administrator_login_password = "Lab@Sql123"     # ⚠️ DUMMY
  minimum_tls_version          = "1.2"
  public_network_access_enabled = true
}

resource "azurerm_mssql_database" "standby" {     # the STANDBY database
  name      = "orders"
  server_id = azurerm_mssql_server.standby.id
  sku_name  = "GP_S_Gen5_1"
  collation = "SQL_Latin1_General_CP1_CI_AS"
  storage_account_type = "Local"
}

resource "random_string" "sa" {                # unique storage suffix
  length  = 4                                    # 4 chars
  special = false                                # no special chars
}

resource "azurerm_storage_account" "standby" {   # the STANDBY blob storage
  name                = "sadrlab${random_string.sa.result}"
  resource_group_name = azurerm_resource_group.dr.name
  location            = azurerm_resource_group.dr.location
  account_tier        = "Standard"
  account_replication_type = "LRS"
}

resource "aws_route53_zone" "lab" {               # your hosted zone (dummy domain)
  name = "dr-lab.example.com"                     # ⚠️ DUMMY — use your own registered domain
}

resource "aws_route53_record" "web_primary" {     # the PRIMARY record (AWS side)
  zone_id = aws_route53_zone.lab.id
  name    = "web-primary"
  type    = "A"
  ttl     = 60
  records = [aws_eip.web.public_ip]
  set_identifier = "dr"                            # ties the failover pair together (v5: required)
  health_check_id = aws_route53_health_check.primary.id   # the health check (v5: separate resource)
}

resource "aws_route53_health_check" "primary" {   # the health check on the AWS primary
  ip_address        = aws_eip.web.public_ip       # what to probe
  port              = 80                          # the port
  type              = "HTTP"                      # probe with HTTP
  resource_path     = "/"                         # the path
  request_interval  = 10                          # every 10s
  failure_threshold = 3                           # 3 fails = unhealthy
}

resource "aws_route53_record" "failover" {        # the record that FAILS OVER
  zone_id = aws_route53_zone.lab.id
  name    = "app"
  type    = "CNAME"

  set_identifier = "dr"                            # ties the failover pair together (v5: required)

  failover_routing_policy {                       # the failover policy
    type = "PRIMARY"                              # (the pair flips to the Azure side when AWS fails)
  }

  records = [azurerm_linux_web_app.standby.default_hostname]   # the CNAME target (the Azure standby)
}

resource "aws_eip" "web" {                        # a static IP for the primary
  domain = "vpc"                                # a VPC-attached EIP (v5: domain, not vpc)
}
