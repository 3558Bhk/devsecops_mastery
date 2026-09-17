# ============================================================================
#  Systems Manager — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_vpc" "main" {                      # the VPC
  cidr_block = "10.0.0.0/16"                     # the space
}

resource "aws_subnet" "a" {                      # the subnet
  vpc_id            = aws_vpc.main.id            # which VPC
  cidr_block        = "10.0.1.0/24"              # inside
  availability_zone = "us-east-1a"               # AZ a
}

data "aws_iam_policy_document" "instance_assume" {   # who may assume the instance role
  statement {
    effect  = "Allow"                             # allow
    actions = ["sts:AssumeRole"]                  # the assume action
    principals {
      type        = "Service"                     # a service
      identifiers = ["ec2.amazonaws.com"]        # the instance
    }
  }
}

resource "aws_iam_role" "instance" {             # the instance role
  name               = "lab-s3ssm-instance"     # the role's name
  assume_role_policy = data.aws_iam_policy_document.instance_assume.json   # the trust document
}

resource "aws_iam_role_policy_attachment" "ssm" {   # the SSM managed policy (the key one)
  role       = aws_iam_role.instance.id         # which role
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"   # SSM + SSM Parameter Store
}

resource "aws_iam_instance_profile" "ssm" {        # wrap the role into an instance profile
  name = "lab-ssm-instance-profile"              # the profile's name
  role = aws_iam_role.instance.name               # which role
}

data "aws_ami" "al2023" {                         # the base AMI
  most_recent = true                               # the latest
  owners      = ["amazon"]                         # from Amazon

  filter {                                        # AL2023 x86
    name   = "name"                               # by name
    values = ["al2023-ami-2023*-x86_64"]          # the pattern
  }
}

resource "aws_instance" "ssm" {                   # the instance
  ami                    = data.aws_ami.al2023.id # the AMI
  instance_type          = "t4g.micro"            # the cheapest (free tier)
  subnet_id              = aws_subnet.a.id        # which subnet
  vpc_security_group_ids = [aws_security_group.ssm.id]   # the firewall
  iam_instance_profile   = aws_iam_instance_profile.ssm.name   # the profile (SSM)
}

resource "aws_security_group" "ssm" {             # the firewall (NO port 22!)
  name   = "ssm-only"                             # the group's name
  vpc_id = aws_vpc.main.id                        # which VPC

  # No inbound SSH — you connect via SSM Session Manager (no open 22).
  # Egress is all-allowed so the SSM agent can reach the SSM API.
  egress {                                       # allow out
    from_port   = 0                              # all ports
    to_port     = 0                              # all ports
    protocol    = "-1"                           # all protocols
    cidr_blocks = ["0.0.0.0/0"]                 # anywhere
  }
}

resource "aws_ssm_parameter" "env" {              # a simple (string) parameter
  name  = "/lab/env"                              # the path-style name
  type  = "String"                                # plain string
  value = "dev"                                   # the value
}

resource "aws_ssm_parameter" "app_version" {      # a parameter with a tier
  name  = "/lab/app/version"                       # the name
  type  = "String"                                 # plain string
  value = "1.0.0"                                  # the value
  tier  = "Standard"                               # the tier (Default/Standard/Advanced)
}
