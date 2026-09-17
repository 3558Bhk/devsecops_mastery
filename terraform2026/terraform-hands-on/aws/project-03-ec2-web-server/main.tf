terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }   # AWS provider, any 5.x
  }
}

provider "aws" {                                 # configure the AWS provider
  region = "us-east-1"                           # where the instance will run
}

data "aws_ami" "al2023" {                        # data block: READ an existing thing (don't create it)
  most_recent = true                             # pick the newest matching image
  owners      = ["amazon"]                       # only official Amazon images

  filter {                                          # a filter: only AMIs matching this
    name   = "name"                                 # filter on the image name
    values = ["al2023-ami-2023*-x86_64"]            # match "Amazon Linux 2023" 64-bit
  }
}

resource "aws_security_group" "web" {            # a security group = a stateful firewall
  name        = "web-sg-${var.environment}"     # unique name per environment
  description = "Allow SSH and HTTP"            # human-readable label
  # NOTE: no vpc_id on purpose — without it, the group attaches to your default VPC

  ingress {                                       # a rule: allow traffic IN
    description = "SSH from your IP only"        # label for this rule
    from_port   = 22                             # port 22 (SSH)
    to_port     = 22                             # same port (single port)
    protocol    = "tcp"                          # TCP protocol
    cidr_blocks = [var.allowed_cidr]             # only this source IP may connect
  }

  ingress {                                       # second rule
    description = "HTTP from anywhere"           # label
    from_port   = 80                             # port 80 (web)
    to_port     = 80                             # single port
    protocol    = "tcp"                          # TCP
    cidr_blocks = ["0.0.0.0/0"]                  # web traffic allowed from the whole internet
  }

  egress {                                        # a rule: allow traffic OUT (instances need to reach the internet)
    description = "All outbound"                 # label
    from_port   = 0                              # all ports
    to_port     = 0                              # all ports
    protocol    = "-1"                           # -1 = all protocols
    cidr_blocks = ["0.0.0.0/0"]                  # to anywhere
  }

  tags = { Name = "web-${var.environment}" }     # label for finding it in the console
}

resource "aws_instance" "web" {                  # the EC2 instance itself
  ami                    = data.aws_ami.al2023.id   # boot from the image the data source found
  instance_type          = var.instance_type        # size, e.g. t4g.micro
  vpc_security_group_ids = [aws_security_group.web.id]   # apply this firewall to the instance

  # script AWS runs ONCE at first boot (bash heredoc — no comment allowed after the EOF marker!)
  user_data = <<-EOF
    #!/bin/bash
    yum update -y && yum install -y httpd        # update packages, install Apache web server
    systemctl enable --now httpd                 # start it now and on every reboot
    echo "Hello from Terraform!" > /var/www/html/index.html   # the web page visitors see
  EOF

  tags = { Name = "web-server-${var.environment}" }   # label for the console
}
