# ============================================================================
#  AMI — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

data "aws_ami" "al2023" {                        # data block: query the catalog of official AMIs
  most_recent = true                             # the newest one
  owners      = ["amazon"]                       # only Amazon's official images
  filter {
    name   = "name"                                 # filter on the image name
    values = ["al2023-ami-2023*-x86_64"]            # the Amazon Linux 2023 x86 pattern
  }
  # → data.aws_ami.al2023.id is the AMI id — never hardcode it
}

resource "aws_instance" "builder" {              # the instance we'll turn into an image
  ami                    = data.aws_ami.al2023.id   # start from the looked-up image
  instance_type          = "t4g.micro"              # smallest (it's just a build box)
  availability_zone      = "us-east-1a"             # a specific AZ (AMI is born in one AZ)

  root_block_device {                               # the root volume (snapshot it later)
    volume_size = 8                                  # 8 GB
    volume_type = "gp3"                              # gp3 (the default SSD)
  }

  # user_data runs on first boot: install what your golden image contains
  # (the build script — no trailing comment on the marker line)
user_data = <<-EOF
    #!/bin/bash
    yum install -y httpd nginx                    # example: two packages
    systemctl enable httpd                        # so the image ships with httpd configured
    echo "built-by-terraform" > /root/origin.txt  # a marker file proving this AMI came from TF
    EOF
}

resource "aws_ebs_snapshot" "root" {               # snapshot the root volume
  volume_id   = aws_instance.builder.root_block_device[0].volume_id   # the root volume
  description = "golden image root snapshot"       # a human note
}

resource "aws_ami" "golden" {                      # the custom AMI (from the snapshot)
  name                = "lab-ami-2026"             # the image's name
  description         = "golden image built by terraform"   # a human note
  virtualization_type = "hvm"                      # the virtualization type
  root_device_name    = "/dev/xvda"                # the root device path
  architecture        = "x86_64"                   # the CPU architecture

  ebs_block_device {                                # the root EBS volume (built from our snapshot)
    device_name = "/dev/xvda"                        # where it shows up in the instance
    snapshot_id = aws_ebs_snapshot.root.id           # built FROM this snapshot (the v5 way)
    volume_size = 8                                  # 8 GB (must be >= the snapshot size)
    volume_type = "gp3"                              # the volume type
  }
}
