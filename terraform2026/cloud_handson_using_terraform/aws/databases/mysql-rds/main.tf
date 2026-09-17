# ============================================================================
#  MySQL (RDS) — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_vpc" "main" {                      # the VPC
  cidr_block = "10.0.0.0/16"                     # the address space
  tags       = { Name = "rds-lab" }              # a label
}

resource "aws_subnet" "a" {                      # private subnet A (RDS subnets)
  vpc_id            = aws_vpc.main.id            # which VPC
  cidr_block        = "10.0.1.0/24"              # inside
  availability_zone = "us-east-1a"               # AZ a
}

resource "aws_subnet" "b" {                      # private subnet B (RDS subnets)
  vpc_id            = aws_vpc.main.id            # which VPC
  cidr_block        = "10.0.2.0/24"              # inside
  availability_zone = "us-east-1b"               # AZ b (RDS wants ≥2 AZs)
}

resource "aws_db_subnet_group" "private" {       # the set of subnets RDS may use
  name       = "rds-private"                     # the group's name
  subnet_ids = [aws_subnet.a.id, aws_subnet.b.id]   # the subnets (≥2 AZs)
  tags       = { Name = "rds-private" }          # a label
}

resource "aws_security_group" "app" {            # the app tier's SG (the client)
  name   = "app-sg"                              # the group's name
  vpc_id = aws_vpc.main.id                       # which VPC
}

resource "aws_security_group" "db" {             # the database's SG
  name   = "db-sg"                               # the group's name
  vpc_id = aws_vpc.main.id                       # which VPC

  ingress {                                       # the ONLY ingress: MySQL port, from the app SG
    description = "MySQL from app tier"          # a label
    from_port   = 3306                           # the MySQL port
    to_port     = 3306                           # the same
    protocol    = "tcp"                          # TCP
    security_groups = [aws_security_group.app.id] # from the app group (SG reference)
  }
}

resource "random_password" "db" {                # generate a strong password (never hardcode)
  length  = 20                                   # 20 chars
  special = true                                 # with specials
}

resource "aws_db_instance" "mysql" {             # the RDS instance
  identifier        = "lab-mysql"                 # the instance's name
  engine            = "mysql"                     # the engine
  engine_version    = "8.0"                       # MySQL 8.0
  instance_class    = "db.t4g.micro"             # the smallest class
  allocated_storage = 20                          # 20 GB (gp2, minimum)
  storage_encrypted = true                        # encrypt at rest (KMS default key)

  db_name  = "appdb"                              # the initial database
  username = "labadmin"                           # the master user
  password = random_password.db.result            # the generated password

  db_subnet_group_name   = aws_db_subnet_group.private.name   # which subnets
  vpc_security_group_ids = [aws_security_group.db.id]         # which firewall

  multi_az                    = false             # false = cheapest (true = synchronous standby in a 2nd AZ)
  backup_retention_period     = 1                 # keep 1 day of automated backups
  deletion_protection         = false             # lab: allow destroy (prod: true!)
  skip_final_snapshot         = true              # don't pause on destroy asking for a final snapshot
  publicly_accessible         = false             # private only
}
