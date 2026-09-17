# ============================================================================
#  Security Groups — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_vpc" "main" {                      # a VPC (security groups live inside a VPC)
  cidr_block = "10.0.0.0/16"                     # the address space
  tags       = { Name = "sg-lab" }               # a label
}

resource "aws_security_group" "app" {            # the app tier's security group
  name        = "app-sg"                         # the group's name
  description = "Allow HTTPS in, everything out" # the group's description (shows in the console)
  vpc_id      = aws_vpc.main.id                  # which VPC it belongs to

  # ingress rules: WHAT may come IN
  ingress {                                       # rule 1: the world may use HTTPS
    description = "HTTPS from anywhere"          # a label for this rule
    from_port   = 443                            # the start port
    to_port     = 443                            # the end port
    protocol    = "tcp"                          # the transport
    cidr_blocks = ["0.0.0.0/0"]                  # from any IPv4 address
  }

  ingress {                                       # rule 2: the app tier may talk to itself
    description = "app tier internal"            # a label
    from_port   = 0                              # all ports
    to_port     = 0                              # (0/0 = any)
    protocol    = "-1"                           # all protocols
    self        = true                           # from instances IN THIS SAME SG
  }

  # egress rules: WHAT may go OUT
  egress {                                        # default: everything out (stateful: replies are auto-allowed anyway)
    description = "allow all outbound"           # a label
    from_port   = 0                              # all ports
    to_port     = 0                              # (0/0 = any)
    protocol    = "-1"                           # all protocols
    cidr_blocks = ["0.0.0.0/0"]                  # to anywhere
  }
}

resource "aws_security_group" "db" {             # the database tier's security group
  name        = "database-sg"                    # the group's name
  description = "Postgres from the app tier only" # the description
  vpc_id      = aws_vpc.main.id                  # which VPC

  ingress {                                       # the ONLY ingress: postgres port, from the app SG
    description = "Postgres from app tier"       # a label
    from_port   = 5432                           # the postgres port
    to_port     = 5432                           # the same
    protocol    = "tcp"                          # over TCP
    security_groups = [aws_security_group.app.id] # from members of the APP group (SG reference — no IPs)
  }

  egress {                                        # a DB rarely initiates: allow DNS + NTP out
    description = "DNS out"                      # a label
    from_port   = 53                             # the DNS port
    to_port     = 53                             # the same
    protocol    = "udp"                          # DNS over UDP
    cidr_blocks = ["10.0.0.0/16"]                # only to the VPC's DNS resolvers
  }
}
