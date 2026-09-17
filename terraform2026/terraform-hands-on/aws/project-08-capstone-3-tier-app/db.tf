# ── DATABASE TIER: RDS PostgreSQL ─────────────────────────────────────────────

resource "aws_db_subnet_group" "db" {               # where RDS may live (must be inside subnets)
  name       = "${var.project}-db"                  # unique name
  subnet_ids = module.vpc.subnet_ids                # both subnets from the module
}

resource "aws_security_group" "db" {                # firewall for the database
  name        = "${var.project}-db-sg"             # unique per project
  description = "Postgres from the web tier only"   # human label
  vpc_id      = module.vpc.vpc_id                   # inside the module's VPC

  ingress {                                          # allow ONLY the web tier to connect
    description = "Postgres from web servers"        # label
    from_port   = 5432                              # the Postgres port
    to_port     = 5432                              # single port
    protocol    = "tcp"                             # TCP
    security_groups = [aws_security_group.web.id]   # source = the web SG's instances (not an open CIDR!)
  }

  egress {                                           # RDS needs almost no outbound; allow all for the lab
    from_port   = 0                                 # all ports
    to_port     = 0                                 # all ports
    protocol    = "-1"                              # all protocols
    cidr_blocks = ["0.0.0.0/0"]                     # anywhere
  }

  tags = { Name = "${var.project}-db" }              # label
}

resource "aws_db_instance" "db" {                   # the PostgreSQL instance
  identifier        = "${var.project}-db"           # unique name for the instance
  engine            = "postgres"                    # the database engine
  engine_version    = "16"                          # major version 16 (Terraform picks the newest 16.x)
  instance_class    = "db.t4g.micro"                # smallest class (free-tier friendly)
  allocated_storage = 20                            # 20 GB of storage (minimum)
  db_name           = var.db_name                   # the initial database created on first boot
  username          = var.db_username               # the admin user
  password          = var.db_password               # the admin password (marked sensitive in variables.tf)
  port              = 5432                          # the port Postgres listens on

  db_subnet_group_name = aws_db_subnet_group.db.name   # which subnets
  vpc_security_group_ids = [aws_security_group.db.id]  # which firewall
  publicly_accessible = true                          # LAB ONLY: so you can psql from your laptop
  skip_final_snapshot = true                          # don't keep a backup snapshot at destroy (saves money)
  deletion_protection = false                         # allow destroy (real prod: true)
}
