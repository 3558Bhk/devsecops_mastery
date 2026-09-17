# AWS 3 — EC2 Compute

> **⏱️ Time to complete: ~50 min** (read + launch an instance with a launch template)

## 3.1 The Core: `aws_instance`

```hcl
data "aws_ami" "ubuntu" {                   # find an AMI (read-only lookup)
  most_recent = true                        # the most recent matching AMI
  owners      = ["099720109477"]            # Canonical (Ubuntu)
  filter {                                   # a name filter
    name   = "name"                          # filter by the AMI name
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]  # Ubuntu 22.04
  }
  filter {                                   # a virtualization-type filter
    name   = "virtualization-type"           # filter by virtualization
    values = ["hvm"]                         # HVM only
  }
}

resource "aws_key_pair" "ssh" {             # an SSH key pair
  key_name   = "${local.name_prefix}-key"   # the key name
  public_key = var.ssh_public_key           # the public key (the private key stays local)
}

resource "aws_instance" "web" {             # an EC2 instance (repeated by count)
  count               = var.instance_count  # N instances
  ami                 = data.aws_ami.ubuntu.id   # the AMI
  instance_type       = var.instance_type   # the instance size
  subnet_id           = module.vpc.private_subnet_ids[count.index % length(module.vpc.private_subnet_ids)]   # spread across subnets
  vpc_security_group_ids = [aws_security_group.web.id]   # the security group(s)
  key_name            = aws_key_pair.ssh.key_name   # the SSH key
  iam_instance_profile = aws_iam_instance_profile.ec2.name   # the instance profile (role)

  user_data = templatefile("${path.module}/user_data.sh.tmpl", {   # bootstrap script
    environment = var.environment   # template variable
  })
  user_data_replace_on_change = true   # restart the user_data script when it changes

  root_block_device {                     # the root volume
    volume_size = 20                       # 20 GB
    volume_type = "gp3"                    # gp3
    encrypted   = true                     # encrypted
    iops        = 3000                     # IOPS
    throughput  = 125                      # throughput (MB/s)
  }

  metadata_options {                      # IMDS settings
    http_tokens = "required"               # IMDSv2 (security: prevents SSRF credential theft)
    http_endpoint = "enabled"              # IMDS enabled
  }

  monitoring = false                       # detailed CloudWatch monitoring off

  tags = { Name = "${local.name_prefix}-web-${count.index}" }   # per-instance name
}
```

## 3.2 AMI Selection (the data source you'll use most)

```hcl
# By owner (Canonical/Amazon/RedHat) + name filter — most common
data "aws_ami" "ubuntu" { ... }        # as above

# By exact id (for custom Packer AMIs)
data "aws_ami" "custom" {
  owners      = ["self"]               # your own account
  most_recent = true                   # the most recent
  filter { name = "name"; values = ["packer-web-20260901"] }   # the Packer AMI name
}

# By AMI id directly
data "aws_ami" "pinned" {
  owners = ["self"]                     # your account
  filter { name = "image-id"; values = ["ami-0abc..."] }   # a specific AMI id
}

# Latest Amazon Linux 2023
data "aws_ami" "al2023" {              # find Amazon Linux 2023
  most_recent = true                    # the most recent
  owners      = ["amazon"]              # owned by Amazon
  filter { name = "name"; values = ["al2023-ami-2023*-x86_64"] }   # the name pattern
  filter { name = "architecture"; values = ["x86_64"] }   # the architecture
}
```

> **Packer** (HashiCorp's AMI builder) is the right tool for *building* AMIs with pre-installed software — then Terraform just *references* the AMI id. Never bake long install scripts into `user_data` if you can avoid it.

## 3.3 Block Devices (storage)

```hcl
root_block_device {                     # the root volume
  volume_size = 30                      # 30 GB
  volume_type = "gp3"                   # gp3 (default, 3000 IOPS/125 MBps baseline), io2, io2_block_expression, st1, sc1, gp2
  encrypted   = true                    # ALWAYS for prod
  iops        = 6000                    # only for gp3/io2 (beyond baseline)
  throughput  = 250                     # MB/s
  tags        = { Name = "root" }       # tag the volume
  delete_on_termination = true          # default (delete the volume when the instance dies)
}

ebs_block_device {                      # an additional EBS volume
  device_name = "/dev/sdf"              # or xvd* / nvme* naming
  volume_size = 100                     # 100 GB
  volume_type = "gp3"                   # gp3
  encrypted   = true                    # encrypted
  iops        = 3000                    # IOPS
  throughput  = 125                     # MB/s
  tags        = { Name = "data" }       # tag
}

ephemeral_block_device {                # an instance-store (ephemeral) volume
  device_name = "/dev/sdb"              # the device name
  virtual_name = "ephemeral0"           # the instance-store index (not all types)
}
```

## 3.4 User Data (bootstrap)

```hcl
# user_data.sh.tmpl   (the bootstrap script template)
#!/bin/bash
set -euo pipefail                        # fail fast on errors
exec > >(tee /var/log/user-data.log) 2>&1   # log everything to a file
apt-get update                           # update the package index
apt-get install -y nginx                 # install nginx
systemctl enable --now nginx             # enable + start nginx
echo "${environment}" > /etc/motd        # write the environment to the motd
```

- `user_data` runs **once at first boot** (cloud-init). Changes require `user_data_replace_on_change = true` (restart) or an instance **replace** to take effect.
- For anything that must be **re-runnable/idempotent**, use a **config management tool** (Ansible) or **cloud-init with per-boot** — not user_data.
- Secrets in user_data are visible in state and the console → don't.

## 3.5 Instance Types (know the families)

| Family | Use | Examples |
|---|---|---|
| `t` (burstable) | Dev, low baseline CPU | t3.small, t3.medium |
| `m` (general) | Most apps | m6i.large, m7i.xlarge |
| `c` (compute) | CPU-heavy | c6i.2xlarge |
| `r` (memory) | DB, caches | r6i.xlarge |
| `x` / `u` (huge memory) | In-mem DBs | x2idn.16xlarge |
| `g` (GPU) | ML, graphics | g5.xlarge, g6e.48xlarge |
| `h` (high throughput) | HPC | hpc7g.16xlarge |
| `inf` / `trn` (AI chips) | Inferentia/Trainium | inf1.6xlarge, trn1.32xlarge |
| Arm | `*g` / `*gr` / `*gd` | m7g.large (cheaper perf) |

Sizing: `.nano .micro .small .medium .large .xlarge .2xlarge .4xlarge .12xlarge .16xlarge .48xlarge` etc.

**Rule:** dev = `t3.small`/`t4g.small`; prod web = `m6i.large`+; DB = `db.*` (managed); ML = `g*`.

## 3.6 Spot Instances (80–90% cheaper, can be interrupted)

```hcl
resource "aws_instance" "spot" {            # a spot EC2 instance
  ami           = data.aws_ami.ubuntu.id   # the AMI
  instance_type = "c6i.xlarge"             # the type

  instance_market_options {                 # market options (on-demand vs spot)
    market_type = "spot"                    # buy as spot
    spot_options {                          # the spot-specific options
      max_price           = "0.08"          # the max price (or "0" = on-demand cap, common)
      spot_instance_type  = "one-time"      # or "persistent" (retries on interruption)
      instance_interruption_behavior = "stop"  # stop | terminate | hibernate
    }
  }
}
```

Best for: batch, CI runners, stateless web (with ASG), ML training. Worst for: anything stateful without persistence.

## 3.7 Launch Templates (the ASG foundation)

```hcl
resource "aws_launch_template" "web" {      # a launch template (instance blueprint)
  name_prefix   = "${local.name_prefix}-web-"   # name prefix (AWS appends an id)
  image_id      = data.aws_ami.ubuntu.id   # the AMI
  instance_type = var.instance_type        # the type

  vpc_security_group_ids = [aws_security_group.web.id]   # the SGs
  iam_instance_profile   = aws_iam_instance_profile.ec2.name   # the instance profile
  key_name               = aws_key_pair.ssh.key_name   # the SSH key

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tmpl", {}))   # base64 bootstrap

  metadata_options {                        # IMDS
    http_tokens = "required"                 # IMDSv2
  }

  block_device_mappings {                   # the root block device
    device_name = "/dev/xvda"                # the root device
    ebs {                                    # the EBS settings
      volume_size = 20                       # 20 GB
      volume_type = "gp3"                    # gp3
      encrypted   = true                     # encrypted
    }
  }

  tag_specifications {                      # tags to apply to the instance
    resource_type = "instance"               # tag the instance
    tags = { Name = "${local.name_prefix}-web" }
  }

  # multiple versions; ASG picks "$Latest" or a specific version
}
```

Launch templates decouple **instance definition** from **scaling policy** — the ASG references a template + version.

## 3.8 Instance Lifecycle Attributes

| Attribute | Notes |
|---|---|
| `ami` | Changing = **replace** (new instance). |
| `instance_type` | Often **in-place** resize (stop/start), sometimes replace. |
| `subnet_id` / `az` | Changing = **replace** (moves the instance). |
| `vpc_security_group_ids` | In-place. |
| `key_name` | In-place (only for new SSH, not existing). |
| `user_data` | In-place but only re-runs with `user_data_replace_on_change`. |
| `iam_instance_profile` | In-place. |
| `tags` | In-place. |

## 3.9 Instance Metadata & IMDS

- **IMDSv1** (open) vs **IMDSv2** (token-based, `http_tokens = "required"`). IMDSv2 prevents the SSRF "stolen role credentials" class of attacks.
- Instance profile → role → permissions the instance's apps get (e.g. read S3).
- **IRSA** (EKS) and **Instance Profiles** (EC2) are the modern, keyless auth for apps.

## 3.10 Related Resources

```hcl
# Instance store / EBS attachment (manual)
resource "aws_volume_attachment" "data" {   # attach an EBS volume to an instance
  device_name = "/dev/sdf"                  # the device name
  volume_id   = aws_ebs_volume.data.id      # the volume
  instance_id = aws_instance.web.id         # the instance
}

# Capacity reservation (guarantee capacity)
resource "aws_ec2_capacity_reservation" "web" {   # a capacity reservation
  instance_type        = "m6i.large"       # the type
  instance_count       = 3                 # how many
  availability_zone    = "ap-south-1a"     # the AZ
  instance_match_criteria = "open"         # open (any template) vs target
}

# Instance metadata options are per-instance (set in aws_instance or launch template)
```

## 3.11 Getting It Right

- **Always set `metadata_options.http_tokens = "required"`** (IMDSv2).
- **Always encrypt** EBS (`encrypted = true`); bring your own KMS CMK for prod.
- **Prefer Launch Templates + ASG** over bare `aws_instance` for anything that should scale.
- **Prefer a Packer AMI** over long `user_data` scripts.
- **Spot** for cheap/stateless; **on-demand** for stateful.
- **Don't** put secrets in `user_data` or tags.
- **`user_data_replace_on_change`** is the only way user_data re-runs on in-place update.

## 3.12 Interview Quick Facts

- EC2 = 1 VM; **ECS/EKS** = containers; **Lambda** = functions (see serverless chapter).
- **Launch Template** = reusable instance definition; **ASG** = the scaler that consumes it.
- **IMDSv2** = token-based metadata (security must).
- **Spot** = interruptible, cheap; best stateless/batch.
- Changing `ami`/`subnet_id` = **replace**; changing `instance_type`/SGs = **in-place**.
- `gp3` is the default EBS type (3000 IOPS baseline); `io2` for high-IOPS.
- **Packer** builds AMIs; **Terraform** consumes them.
