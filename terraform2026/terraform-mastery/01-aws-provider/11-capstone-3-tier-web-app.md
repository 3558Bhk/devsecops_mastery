# AWS 11 — Capstone: A Complete 3-Tier Web App

> **⏱️ Time to complete: ~2.5–3 hrs** (full hands-on build: VPC → ALB/ASG → RDS → CloudFront)

This is the "put it all together" build. A production-shaped 3-tier app on AWS:

```
Route53 (www.example.com)
   → CloudFront (CDN, TLS, WAF)
   → S3 (static site)  +  ALB
   → ALB (public) → ASG (web, private) → RDS Postgres (private, isolated)
   + IAM roles, tags, CloudWatch alarm, S3 app bucket, secrets
```

## 11.1 File Layout

```
capstone/
├── versions.tf
├── backend.tf
├── providers.tf
├── variables.tf
├── locals.tf
├── data.tf
├── network.tf        # VPC (reuse a module or inline)
├── compute.tf        # ALB + ASG + launch template
├── database.tf       # RDS
├── static.tf         # S3 + CloudFront + Route53
├── security.tf       # IAM, SGs, KMS
├── observability.tf  # alarms, log groups
└── outputs.tf
```

## 11.2 `versions.tf`

```hcl
terraform {                          # the terraform config block
  required_version = ">= 1.9"        # require Terraform 1.9 or newer
  required_providers {               # declare the providers
    aws = { source = "hashicorp/aws"; version = "~> 5.0" }        # the AWS provider (5.x)
    random = { source = "hashicorp/random"; version = "~> 3.0" }  # the random provider (3.x)
  }
}
```

## 11.3 `providers.tf`

```hcl
provider "aws" {                      # configure the AWS provider
  region  = var.region                # target region
  profile = var.profile               # shared-credentials profile
  default_tags = {                    # tags applied to everything
    Project     = var.project         #  project
    Environment = var.environment     #  environment
    ManagedBy   = "terraform"         #  managed-by
    CostCenter  = var.cost_center     #  cost center
  }
}
```

## 11.4 `variables.tf` (the public API)

```hcl
variable "project"       { type = string; default = "webapp" }     # the project name
variable "environment"   { type = string; default = "dev" }        # the environment
variable "region"        { type = string; default = "ap-south-1" } # the AWS region
variable "profile"       { type = string; default = "default" }    # the credentials profile
variable "cost_center"   { type = string; default = "1001" }       # the cost center
variable "vpc_cidr"      { type = string; default = "10.40.0.0/16" }   # the VPC CIDR
variable "az_count"      { type = number; default = 2 }            # how many AZs
variable "instance_type" { type = string; default = "t3.small" }   # the web instance type
variable "db_instance"   { type = string; default = "db.t4g.micro" }   # the DB instance class
variable "ssh_public_key" { type = string; default = "" }          # (optional) SSH public key
variable "domain"        { type = string; default = "example.com" }    # the domain
variable "route53_zone"  { type = string; default = "example.com" }    # the Route 53 zone
variable "approval_token" { type = string; default = "" }        # (optional) prod approval token
```

## 11.5 `locals.tf`

```hcl
locals {                          # named expressions
  name_prefix = "${var.project}-${var.environment}"   # e.g. "webapp-dev"
  prod        = (var.environment == "prod")           # true only in prod (gates safety)
}
```

## 11.6 `network.tf` (compact, single-file for the capstone)

```hcl
data "aws_availability_zones" "available" { state = "available" }   # the available AZs
data "aws_region" "current" {}               # the current region
data "aws_caller_identity" "me" {}           # the current account

locals {                                      # derived values
  azs           = slice(data.aws_availability_zones.available.names, 0, var.az_count)  # first N AZs
  public_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i)]        # public subnet CIDRs
  private_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 100)]  # private subnet CIDRs
  db_cidrs      = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 200)]  # db subnet CIDRs
}

resource "aws_vpc" "main" {                    # the VPC
  cidr_block           = var.vpc_cidr          # the CIDR
  enable_dns_support   = true                  # DNS support
  enable_dns_hostnames = true                  # DNS hostnames
  tags                 = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "main" {       # the internet gateway
  vpc_id = aws_vpc.main.id                     # the VPC
  tags   = { Name = "${local.name_prefix}-igw" }
}

resource "aws_subnet" "public" {               # public subnets (one per AZ)
  count             = var.az_count             # one per AZ
  vpc_id            = aws_vpc.main.id          # the VPC
  cidr_block        = local.public_cidrs[count.index]   # the CIDR
  availability_zone = local.azs[count.index]   # the AZ
  tags              = { Name = "${local.name_prefix}-public-${count.index}" }
}

resource "aws_subnet" "private" {              # private subnets (one per AZ)
  count             = var.az_count             # one per AZ
  vpc_id            = aws_vpc.main.id          # the VPC
  cidr_block        = local.private_cidrs[count.index]   # the CIDR
  availability_zone = local.azs[count.index]   # the AZ
  tags              = { Name = "${local.name_prefix}-private-${count.index}" }
}

resource "aws_subnet" "db" {                   # db subnets (one per AZ)
  count             = var.az_count             # one per AZ
  vpc_id            = aws_vpc.main.id          # the VPC
  cidr_block        = local.db_cidrs[count.index]   # the CIDR
  availability_zone = local.azs[count.index]   # the AZ
  tags              = { Name = "${local.name_prefix}-db-${count.index}" }
}

resource "aws_eip" "nat" { count = 1; domain = "vpc"; depends_on = [aws_internet_gateway.main] }  # the NAT's EIP

resource "aws_nat_gateway" "main" {            # the NAT gateway
  count         = 1                            # one NAT
  allocation_id = aws_eip.nat[0].id            # the EIP
  subnet_id     = aws_subnet.public[0].id      # in a public subnet
  depends_on    = [aws_internet_gateway.main]  # wait for the IGW
}

resource "aws_route_table" "public" {          # the public route table
  vpc_id = aws_vpc.main.id                     # the VPC
  route { cidr_block = "0.0.0.0/0"; gateway_id = aws_internet_gateway.main.id }   # internet via IGW
  tags   = { Name = "${local.name_prefix}-pub-rt" }
}

resource "aws_route_table" "private" {         # the private route table
  vpc_id = aws_vpc.main.id                     # the VPC
  route { cidr_block = "0.0.0.0/0"; nat_gateway_id = aws_nat_gateway.main[0].id }   # internet via NAT
  tags   = { Name = "${local.name_prefix}-priv-rt" }
}

resource "aws_route_table" "db" {              # the db route table
  vpc_id = aws_vpc.main.id                     # the VPC
  tags   = { Name = "${local.name_prefix}-db-rt" }   # NO default route = isolated
}

resource "aws_route_table_association" "public" {   # associate public subnets
  count          = var.az_count                 # one per AZ
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id    # the public RT
}
resource "aws_route_table_association" "private" {   # associate private subnets
  count          = var.az_count                 # one per AZ
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id   # the private RT
}
resource "aws_route_table_association" "db" {   # associate db subnets
  count          = var.az_count                 # one per AZ
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id        # the db RT
}

# S3 gateway endpoint (private S3 access)
resource "aws_vpc_endpoint" "s3" {             # the S3 gateway endpoint
  vpc_id            = aws_vpc.main.id          # the VPC
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"   # the S3 service
  vpc_endpoint_type = "Gateway"                # gateway type
  route_table_ids   = [aws_route_table.private.id, aws_route_table.db.id]   # private + db RTs
}
```

## 11.7 `security.tf`

```hcl
resource "aws_kms_key" "db" {                  # a KMS key for the DB
  description             = "RDS encryption"   # description
  deletion_window_in_days = 30                 # 30-day deletion window
  enable_key_rotation     = true               # auto-rotate
}

resource "aws_key_pair" "ssh" {                # an SSH key (only if a key was provided)
  count      = var.ssh_public_key != "" ? 1 : 0   # conditional count
  key_name   = "${local.name_prefix}-key"    # the key name
  public_key = var.ssh_public_key             # the public key
}

# ALB SG (allow 80/443 from anywhere)
resource "aws_security_group" "alb" {          # the ALB security group
  name_prefix = "${local.name_prefix}-alb-"    # name prefix
  vpc_id      = aws_vpc.main.id                # the VPC
  ingress {                                     # allow HTTP
    description = "http"
    from_port   = 80; to_port = 80; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {                                     # allow HTTPS
    description = "https"
    from_port   = 443; to_port = 443; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"]
  }
  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }   # allow all out
}

# Web SG (allow 80 from ALB only)
resource "aws_security_group" "web" {          # the web security group
  name_prefix = "${local.name_prefix}-web-"    # name prefix
  vpc_id      = aws_vpc.main.id                # the VPC
  ingress {                                     # allow HTTP from the ALB
    description     = "http from ALB"
    from_port       = 80; to_port = 80; protocol = "tcp"
    security_groups = [aws_security_group.alb.id]   # only from the ALB SG
  }
  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }   # allow all out
}

# DB SG (allow 5432 from web only)
resource "aws_security_group" "db" {           # the db security group
  name_prefix = "${local.name_prefix}-db-"     # name prefix
  vpc_id      = aws_vpc.main.id                # the VPC
  ingress {                                     # allow postgres from the web SG
    description     = "postgres from web"
    from_port       = 5432; to_port = 5432; protocol = "tcp"
    security_groups = [aws_security_group.web.id]   # only from the web SG
  }
  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }   # allow all out
}

# EC2 role
data "aws_iam_policy_document" "ec2_assume" {   # the EC2 trust doc
  statement { effect = "Allow"; actions = ["sts:AssumeRole"]
    principals { type = "Service"; identifiers = ["ec2.amazonaws.com"] } }  # trusted by EC2
}

resource "aws_iam_role" "ec2" {               # the EC2 role
  name               = "${local.name_prefix}-ec2"   # role name
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json   # trust policy
  path               = "/"                  # the path
}

resource "aws_iam_role_policy" "ec2" {         # an inline policy on the role
  role = aws_iam_role.ec2.id                  # the role
  policy = jsonencode({                        # the policy document
    Version = "2012-10-17"                      # policy version
    Statement = [{                              # one statement
      Effect = "Allow"                          # allow
      Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "s3:GetObject"]   # logs + s3 read
      Resource = ["*"]                          # (tighten in prod)
    }]
  })
}

resource "aws_iam_instance_profile" "ec2" {   # the instance profile
  name = "${local.name_prefix}-ec2"           # profile name
  role = aws_iam_role.ec2.name                # the role
}
```

## 11.8 `data.tf`

```hcl
data "aws_ami" "ubuntu" {                   # find the Ubuntu AMI
  most_recent = true                        # the most recent
  owners      = ["099720109477"]            # Canonical
  filter { name = "name"; values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"] }  # the name
  filter { name = "virtualization-type"; values = ["hvm"] }  # HVM
}

data "aws_rds_engine_version" "pg" {        # find the postgres version
  engine         = "postgres"               # the engine
  latest_version = true                     # the latest
}
```

## 11.9 `compute.tf`

```hcl
resource "aws_launch_template" "web" {      # the web launch template
  name_prefix   = "${local.name_prefix}-web-"   # name prefix
  image_id      = data.aws_ami.ubuntu.id   # the AMI
  instance_type = var.instance_type        # the type
  vpc_security_group_ids = [aws_security_group.web.id]   # the web SG
  iam_instance_profile   = aws_iam_instance_profile.ec2.name   # the instance profile
  key_name               = var.ssh_public_key != "" ? aws_key_pair.ssh[0].key_name : null   # SSH key (if provided)
  user_data              = templatefile("${path.module}/templates/user_data.sh.tmpl", { env = var.environment })   # bootstrap
  metadata_options { http_tokens = "required" }   # IMDSv2
  block_device_mappings {                   # the root block device
    device_name = "/dev/xvda"                # the root device
    ebs { volume_size = 20; volume_type = "gp3"; encrypted = true }   # 20 GB encrypted gp3
  }
  tag_specifications { resource_type = "instance"; tags = { Name = "${local.name_prefix}-web" } }   # instance tags
}

resource "aws_lb_target_group" "web" {      # the target group
  name        = "${local.name_prefix}-web"  # the name
  port        = 80                          # the port
  protocol    = "HTTP"                      # the protocol
  vpc_id      = aws_vpc.main.id             # the VPC
  health_check { path = "/healthz"; matcher = "200"; interval = 30; timeout = 5 }   # the health check
  deregistration_delay = 30                 # drain on removal
}

resource "aws_lb" "web" {                # the ALB
  name               = "${local.name_prefix}-web"   # the name
  load_balancer_type = "application"     # L7
  subnets            = aws_subnet.public[*].id      # public subnets
  security_groups    = [aws_security_group.alb.id]  # the ALB SG
  enable_deletion_protection = local.prod           # protect (prod)
}

resource "aws_lb_listener" "http" {      # the HTTP listener
  load_balancer_arn = aws_lb.web.arn     # the ALB
  port              = 80                 # port 80
  protocol          = "HTTP"             # HTTP
  default_action { type = "forward"; target_group_arn = aws_lb_target_group.web.arn }   # forward to the TG
}

resource "aws_autoscaling_group" "web" {   # the ASG
  name                = "${local.name_prefix}-web"   # the name
  launch_template { id = aws_launch_template.web.id; version = "$Latest" }   # the template
  min_size         = 2                    # minimum
  max_size         = 4                    # maximum
  desired_capacity = 2                    # starting
  vpc_zone_identifier = aws_subnet.private[*].id   # the private subnets
  health_check_type         = "ELB"        # use the ALB health checks
  health_check_grace_period = 300          # grace period
  instance_refresh { strategy = "Rolling" }   # rolling replace on template change
  tags = [{ key = "Name"; value = "${local.name_prefix}-web"; propagate_at_launch = true }]   # instance tags
}

resource "aws_autoscaling_policy" "cpu" {   # a target-tracking scaling policy
  name                   = "cpu"            # the policy name
  autoscaling_group_name = aws_autoscaling_group.web.name   # the ASG
  policy_type            = "TargetTrackingScaling"   # target tracking
  target_tracking_configuration {           # the target settings
    predefined_metric_type = "ASGAverageCPUUtilization"   # the metric
    target_value           = 60               # keep CPU ~60%
  }
}
```

## 11.10 `database.tf`

```hcl
resource "aws_db_subnet_group" "main" {     # the DB subnet group
  name       = "${local.name_prefix}-db"   # the name
  subnet_ids = aws_subnet.db[*].id         # the db subnets
}

resource "random_password" "db" { length = 20; special = false }   # a 20-char password (no special chars)

resource "aws_secretsmanager_secret" "db" { name = "${local.name_prefix}/db" }   # the secret

resource "aws_secretsmanager_secret_version" "db" {   # the secret value
  secret_id = aws_secretsmanager_secret.db.id   # the secret
  secret_string = jsonencode({                 # the payload
    username = "appadmin"                      # the user
    password = random_password.db.result       # the password
    port     = 5432                            # the port
    dbname   = "app"                           # the database
  })
}

resource "aws_db_instance" "main" {         # the RDS instance
  identifier     = "${local.name_prefix}-db"   # a unique id
  engine         = "postgres"                  # the engine
  engine_version = data.aws_rds_engine_version.pg.version   # the version
  instance_class = var.db_instance             # the size

  allocated_storage     = 20                   # 20 GB
  max_allocated_storage = 100                  # auto-grow to 100 GB
  storage_type          = "gp3"                 # gp3
  storage_encrypted     = true                  # encrypt
  kms_key_id            = aws_kms_key.db.arn    # the CMK

  db_name  = "app"                              # the database
  username = "appadmin"                         # the master user
  password = random_password.db.result          # the master password

  db_subnet_group_name   = aws_db_subnet_group.main.name   # the subnet group
  vpc_security_group_ids = [aws_security_group.db.id]      # the db SG
  multi_az               = local.prod           # HA (prod)
  publicly_accessible    = false                 # never public
  backup_retention_period = 7                    # 7-day backups
  deletion_protection    = local.prod           # protect (prod)
  skip_final_snapshot    = !local.prod          # skip snapshot (dev)

  tags = { Name = "${local.name_prefix}-db" }  # tag
  lifecycle { prevent_destroy = local.prod }   # protect (prod)
}
```

## 11.11 `static.tf` (S3 + CloudFront + Route53)

```hcl
resource "aws_s3_bucket" "site" {           # the static site bucket
  bucket        = "${local.name_prefix}-site-${data.aws_region.current.name}"   # unique name
  force_destroy = !local.prod               # dev-only force destroy
}

resource "aws_s3_bucket_versioning" "site" {   # versioning
  bucket = aws_s3_bucket.site.id               # the bucket
  versioning_configuration { status = "Enabled" }   # enabled
}

resource "aws_s3_bucket_public_access_block" "site" {   # block public access
  bucket = aws_s3_bucket.site.id               # the bucket
  block_public_acls = true; block_public_policy = true
  ignore_public_acls = true; restrict_public_buckets = true   # all four flags on
}

resource "aws_s3_bucket_website_configuration" "site" {   # static website
  bucket = aws_s3_bucket.site.id               # the bucket
  index_document { suffix = "index.html" }     # the index doc
}

# (ACM cert in us-east-1 — provider alias)
provider "aws" { alias = "us_east"; region = "us-east-1" }   # the us-east-1 alias

resource "aws_acm_certificate" "wildcard" {   # the ACM certificate
  provider          = aws.us_east            # in us-east-1
  domain_name       = "*.${var.domain}"       # the wildcard domain
  validation_method = "DNS"                  # DNS validation
  lifecycle { create_before_destroy = true } # create before destroy
}

data "aws_acm_certificate_validation" "wildcard" {   # wait for validation
  provider = aws.us_east                      # us-east-1
  certificate_arn = aws_acm_certificate.wildcard.arn   # the cert
}

resource "aws_cloudfront_origin_access_control" "site" {   # the OAC
  name = "${local.name_prefix}-site-oac"     # the name
  origin_access_control_origin_type = "s3"   # for S3
  signing_behavior = "always"                # always sign
  signing_protocol = "sigv4"                 # SigV4
}

resource "aws_cloudfront_distribution" "site" {   # the CloudFront distribution
  depends_on = [data.aws_acm_certificate_validation.wildcard]   # wait for the cert
  aliases          = ["www.${var.domain}"]   # the custom domain
  default_root_object = "index.html"          # the default object
  price_class      = "PriceClass_100"         # all edges

  origin {                                   # the origin (the S3 bucket)
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name   # the bucket
    origin_id                = "s3-site"     # the origin id
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id   # the OAC
  }

  default_cache_behavior {                   # the default cache behavior
    target_origin_id       = "s3-site"       # the origin
    viewer_protocol_policy = "redirect-to-https"   # force HTTPS
    allowed_methods        = ["GET", "HEAD"]   # allowed methods
    cached_methods         = ["GET", "HEAD"]   # cached methods
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6"   # managed cache policy
  }

  viewer_certificate {                       # the viewer certificate
    acm_certificate_arn      = aws_acm_certificate.wildcard.arn   # the ACM cert
    ssl_support_method       = "sni-only"   # SNI-only
    minimum_protocol_version = "TLSv1.2_2021"   # min TLS
  }

  restrictions { geo_restriction { restriction_type = "none" } }   # no geo restriction
  tags = { Name = "${local.name_prefix}-cf" }
}

data "aws_route53_zone" "main" { name = var.route53_zone }   # the hosted zone

resource "aws_route53_record" "www" {        # the www record
  zone_id = data.aws_route53_zone.main.id   # the zone
  name    = "www.${var.domain}"             # the record name
  type    = "A"                             # an A record
  alias {                                    # alias to CloudFront
    name    = aws_cloudfront_distribution.site.domain_name   # the CFN domain
    zone_id = aws_cloudfront_distribution.site.hosted_zone_id   # the CFN zone
  }
}
```

## 11.12 `observability.tf`

```hcl
resource "aws_cloudwatch_log_group" "app" {   # a log group
  name              = "/${local.name_prefix}/app"   # the name
  retention_in_days = 30                        # 30-day retention
}

resource "aws_sns_topic" "alarms" { name = "${local.name_prefix}-alarms" }   # the alarm topic

resource "aws_cloudwatch_metric_alarm" "cpu" {   # a CPU alarm
  alarm_name          = "${local.name_prefix}-cpu"   # the alarm name
  namespace           = "AWS/EC2"                     # the namespace
  metric_name         = "CPUUtilization"              # the metric
  statistic           = "Average"                     # the statistic
  period              = 300                           # 5-minute period
  evaluation_periods  = 2                             # 2 periods
  threshold           = 80                            # the threshold
  comparison_operator = "GreaterThanThreshold"        # the comparison
  dimensions = { AutoScalingGroupName = aws_autoscaling_group.web.name }   # the ASG
  alarm_actions = [aws_sns_topic.alarms.arn]         # notify the topic
}
```

## 11.13 `outputs.tf`

```hcl
output "alb_dns"        { value = aws_lb.web.dns_name }                    # the ALB DNS name
output "alb_url"        { value = "http://${aws_lb.web.dns_name}" }        # the ALB URL
output "cf_domain"      { value = aws_cloudfront_distribution.site.domain_name }   # the CFN domain
output "site_url"       { value = "https://www.${var.domain}" }            # the site URL
output "db_endpoint"    { value = aws_db_instance.main.address }           # the DB endpoint
output "db_secret_arn"  { value = aws_secretsmanager_secret.db.arn }       # the DB secret ARN
output "account"        { value = data.aws_caller_identity.me.account }    # the account
output "region"         { value = data.aws_region.current.name }           # the region
output "vpc_id"         { value = aws_vpc.main.id }                        # the VPC id
output "private_subnet_ids" { value = aws_subnet.private[*].id }           # the private subnet ids
```

## 11.14 Build & Verify (the workflow)

```bash
terraform init
terraform plan -out=plan
terraform apply plan
# 1) curl http://<alb_dns>/healthz  → 200
# 2) aws rds describe-db-instances
# 3) aws cloudfront list-distributions
# 4) aws route53 list-resource-record-sets --hosted-zone-id <id>
terraform plan    # → "No changes" (idempotent!)
```

**Teardown** (dev):
```bash
terraform destroy -auto-approve
```

## 11.15 What to Study in This Capstone

1. **Dependency order**: VPC → subnets → SGs → (ALB/ASG/DB). Notice Terraform figures it out from references.
2. **Isolation**: the DB subnet has **no** 0.0.0.0/0 route; only the web SG can reach 5432.
3. **Secrets**: `random_password` → Secrets Manager; DB `password` in state (rotate + `sensitive`).
4. **CDN + WAF + TLS**: CloudFront in front of S3 (private) via **OAC**; ACM cert in **us-east-1**.
5. **Idempotency**: run `plan` twice → second is empty.
6. **`local.prod`** gates: `multi_az`, `deletion_protection`, `prevent_destroy`, `force_destroy`.

## 11.16 Extend It (your homework)

- [ ] Add **Aurora** instead of RDS.
- [ ] Add a **DynamoDB** table for sessions.
- [ ] Add a **Lambda** + **API Gateway** for a `/api/health` route.
- [ ] Add **WAF** to CloudFront.
- [ ] Add **S3 replication** to a DR region.
- [ ] Split `network` into its **own root module** + use `terraform_remote_state` in the app.
- [ ] Add **Infracost** to a CI workflow.
- [ ] Add **`terraform test`** (assert 2 instances, DB not public).
