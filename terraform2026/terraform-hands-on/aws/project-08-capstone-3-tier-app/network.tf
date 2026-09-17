# ── NETWORK: we reuse the VPC module built in project 05 ──────────────────────

data "aws_ami" "al2023" {                            # data block: find the newest Amazon Linux 2023 image
  most_recent = true                                 # newest matching image
  owners      = ["amazon"]                           # official Amazon images only
  filter {                                          # a filter: only AMIs matching this
    name   = "name"                                 # filter on the image name
    values = ["al2023-ami-2023*-x86_64"]            # the name pattern
  }
}

module "vpc" {                                       # module block: call the child module from project 05
  source = "../project-05-your-first-module/modules/vpc"   # relative path to that folder
  name   = var.project                               # → the module's var.name
  cidr_block = "10.0.0.0/16"                         # → the module's var.cidr_block
}

resource "aws_security_group" "web" {                # firewall for the web tier
  name        = "${var.project}-web-sg"             # unique per project
  description = "ALB → web servers (HTTP only)"     # human label
  vpc_id      = module.vpc.vpc_id                   # inside the module's VPC

  ingress {                                          # allow the ALB to reach the servers on port 80
    description      = "HTTP from the ALB"           # label
    from_port        = 80                           # port 80
    to_port          = 80                           # port 80
    protocol         = "tcp"                        # TCP
    cidr_blocks      = ["0.0.0.0/0"]                # (ALB security group references are cleaner, but this works for a lab)
  }

  egress {                                           # allow all outbound (servers must reach RDS + the internet for yum)
    description = "All outbound"                     # label
    from_port   = 0                                  # all ports
    to_port     = 0                                  # all ports
    protocol    = "-1"                               # all protocols
    cidr_blocks = ["0.0.0.0/0"]                      # anywhere
  }

  tags = { Name = "${var.project}-web" }             # label
}
