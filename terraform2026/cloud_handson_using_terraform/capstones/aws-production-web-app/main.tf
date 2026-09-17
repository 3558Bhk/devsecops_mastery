# ============================================================================
#  Capstone 1 — AWS Production Web App (full 3-tier)
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_vpc" "main" {                      # the VPC
  cidr_block       = "10.30.0.0/16"             # the address space
  enable_dns_hostnames = true                   # instances get DNS hostnames
  tags = { Name = "prod-vpc" }                  # a label
}

resource "aws_subnet" "public_a" {               # public subnet A
  vpc_id            = aws_vpc.main.id           # which VPC
  cidr_block        = "10.30.0.0/24"            # the slice
  availability_zone = "us-east-1a"              # AZ a
  tags = { Tier = "public" }                    # a label
}

resource "aws_subnet" "public_b" {               # public subnet B
  vpc_id            = aws_vpc.main.id           # which VPC
  cidr_block        = "10.30.1.0/24"            # the slice
  availability_zone = "us-east-1b"              # AZ b
  tags = { Tier = "public" }                    # a label
}

resource "aws_subnet" "private_a" {              # private subnet A (app/db/cache)
  vpc_id            = aws_vpc.main.id           # which VPC
  cidr_block        = "10.30.2.0/24"            # the slice
  availability_zone = "us-east-1a"              # AZ a
  tags = { Tier = "private" }                   # a label
}

resource "aws_subnet" "private_b" {              # private subnet B
  vpc_id            = aws_vpc.main.id           # which VPC
  cidr_block        = "10.30.3.0/24"            # the slice
  availability_zone = "us-east-1b"              # AZ b
  tags = { Tier = "private" }                   # a label
}

resource "aws_internet_gateway" "main" {         # the IGW (public internet edge)
  vpc_id = aws_vpc.main.id                       # which VPC
}

resource "aws_eip" "nat" {                       # the EIP for the NAT GW
  domain = "vpc"                                 # VPC-scoped EIP
  tags   = { Name = "nat-eip" }                  # a label
}

resource "aws_nat_gateway" "main" {              # the NAT GW (private → out)
  allocation_id   = aws_eip.nat.id               # which EIP
  subnet_id       = aws_subnet.public_a.id       # a PUBLIC subnet
  depends_on      = [aws_internet_gateway.main]  # wait for the IGW
}

resource "aws_route_table" "public" {            # the public route table
  vpc_id = aws_vpc.main.id                       # which VPC

  route {                                         # default → IGW
    cidr_block = "0.0.0.0/0"                     # anywhere
    gateway_id = aws_internet_gateway.main.id     # via the IGW
  }
}

resource "aws_route_table" "private" {           # the private route table
  vpc_id = aws_vpc.main.id                       # which VPC

  route {                                         # default → NAT GW
    cidr_block     = "0.0.0.0/0"                 # anywhere
    nat_gateway_id = aws_nat_gateway.main.id      # via the NAT GW
  }
}

resource "aws_route_table_association" "pub_a" {   # public A → public table
  subnet_id      = aws_subnet.public_a.id       # which subnet
  route_table_id = aws_route_table.public.id     # which table
}

resource "aws_route_table_association" "pub_b" {   # public B → public table
  subnet_id      = aws_subnet.public_b.id       # which subnet
  route_table_id = aws_route_table.public.id     # which table
}

resource "aws_route_table_association" "priv_a" {  # private A → private table
  subnet_id      = aws_subnet.private_a.id      # which subnet
  route_table_id = aws_route_table.private.id    # which table
}

resource "aws_route_table_association" "priv_b" {  # private B → private table
  subnet_id      = aws_subnet.private_b.id      # which subnet
  route_table_id = aws_route_table.private.id    # which table
}

resource "aws_network_acl" "private" {       # the NACL on the private subnets
  vpc_id = aws_vpc.main.id                       # which VPC

  ingress {                                      # 100: allow ephemeral (return) traffic
    rule_no     = 100                            # the rule number
    action      = "allow"                     # allow (NACLs are stateless; be explicit)
    protocol    = "tcp"                          # the protocol
    from_port   = 1024                           # the start port (ephemeral range)
    to_port     = 65535                          # the end port
    cidr_block  = "10.30.0.0/16"                 # from the VNet itself
  }

  ingress {                                      # 110: allow MySQL (from the app subnet only)
    rule_no     = 110                            # the rule number
    action      = "allow"                     # allow (NACLs are stateless; be explicit)
    protocol    = "tcp"                          # the protocol
    from_port   = 3306                           # MySQL
    to_port     = 3306                           # MySQL
    cidr_block  = "10.30.0.0/16"                 # from within the VPC (the app)
  }

  ingress {                                      # 120: allow Redis
    rule_no     = 120                            # the rule number
    action      = "allow"                     # allow (NACLs are stateless; be explicit)
    protocol    = "tcp"                          # the protocol
    from_port   = 6379                           # Redis
    to_port     = 6379                           # Redis
    cidr_block  = "10.30.0.0/16"                 # from within the VPC
  }

  egress {                                       # 100: allow outbound to the VPC
    rule_no     = 100                            # the rule number
    action      = "allow"                     # allow (NACLs are stateless; be explicit)
    protocol    = "tcp"                          # the protocol
    from_port   = 0                              # all ports
    to_port     = 0                              # all ports
    cidr_block  = "10.30.0.0/16"                 # to the VPC
  }

  egress {                                       # 110: allow outbound to the internet (via NAT)
    rule_no     = 110                            # the rule number
    action      = "allow"                     # allow (NACLs are stateless; be explicit)
    protocol    = "tcp"                          # the protocol
    from_port   = 0                              # all ports
    to_port     = 0                              # all ports
    cidr_block  = "0.0.0.0/0"                    # to anywhere (patching, etc.)
  }
}

resource "aws_network_acl_association" "priv_a" {   # attach to private A
  subnet_id         = aws_subnet.private_a.id  # which subnet
  network_acl_id    = aws_network_acl.private.id   # which NACL
}

resource "aws_network_acl_association" "priv_b" {   # attach to private B
  subnet_id         = aws_subnet.private_b.id  # which subnet
  network_acl_id    = aws_network_acl.private.id   # which NACL
}

resource "aws_vpc_endpoint" "s3" {               # the S3 GATEWAY endpoint
  vpc_id       = aws_vpc.main.id                # which VPC
  service_name = "com.amazonaws.us-east-1.s3"   # the S3 service

  vpc_endpoint_type = "Gateway"                 # gateway (a route-table entry, no ENI)

  route_table_ids = [aws_route_table.private.id]   # apply to the private tables
}

resource "aws_security_group" "dynamo_ep" {      # the SG for the DynamoDB interface endpoint
  name   = "dynamo-endpoint"                    # the group's name
  vpc_id = aws_vpc.main.id                       # which VPC

  ingress {                                      # TLS to the endpoint ENIs
    description = "HTTPS to the endpoint"       # a label
    from_port   = 443                           # the port
    to_port     = 443                           # the port
    protocol    = "tcp"                         # the protocol
    cidr_blocks = ["10.30.0.0/16"]              # from the VPC
  }
}

resource "aws_vpc_endpoint" "dynamodb" {         # the DynamoDB INTERFACE endpoint
  vpc_id       = aws_vpc.main.id                # which VPC
  service_name = "com.amazonaws.us-east-1.dynamodb"   # the DynamoDB service

  vpc_endpoint_type = "Interface"               # interface (ENIs in subnets)

  subnet_ids          = [aws_subnet.private_a.id, aws_subnet.private_b.id]   # the subnets
security_group_ids  = [aws_security_group.dynamo_ep.id]   # the firewall
  private_dns_enabled = true                    # resolve DynamoDB DNS privately
}

resource "aws_security_group" "web" {            # the app SG (behind the ALB)
  name   = "web-sg"                              # the group's name
  vpc_id = aws_vpc.main.id                       # which VPC

  ingress {                                      # from the ALB only
    description = "from the ALB"                 # a label
    from_port   = 80                           # the port
    to_port     = 80                           # the port
    protocol    = "tcp"                        # the protocol
    cidr_blocks = ["10.30.0.0/16"]             # from the VPC (the ALB)
  }

  egress {                                       # allow out
    from_port   = 0                              # all ports
    to_port     = 0                              # all ports
    protocol    = "-1"                           # all protocols
    cidr_blocks = ["0.0.0.0/0"]                # anywhere
  }
}

resource "aws_security_group" "rds" {            # the RDS SG
  name   = "rds-sg"                              # the group's name
  vpc_id = aws_vpc.main.id                       # which VPC

  ingress {                                      # from the app SG only
    description = "from the app"                 # a label
    from_port   = 3306                         # MySQL
    to_port     = 3306                         # MySQL
    protocol    = "tcp"                        # the protocol
    security_groups = [aws_security_group.web.id]   # the app's SG
  }
}

resource "aws_security_group" "cache" {          # the ElastiCache SG
  name   = "cache-sg"                            # the group's name
  vpc_id = aws_vpc.main.id                       # which VPC

  ingress {                                      # from the app SG only
    description = "from the app"                 # a label
    from_port   = 6379                         # Redis
    to_port     = 6379                         # Redis
    protocol    = "tcp"                        # the protocol
    security_groups = [aws_security_group.web.id]   # the app's SG
  }
}

resource "aws_kms_key" "app" {                   # a customer-managed key
  description             = "capstone app key"   # a description
  enable_key_rotation     = true                 # auto-rotate
  deletion_window_in_days = 7                    # the deletion window
}

resource "random_password" "db" {                # a random DB password
  length  = 20                                   # 20 chars
  special = true                                 # include special chars
}

resource "aws_secretsmanager_secret" "db" {      # the secret (metadata)
  name       = "prod/db-credentials"             # the secret's name
  description = "the app DB credentials"         # a description
}

resource "aws_secretsmanager_secret_version" "db" {   # the secret (value)
  secret_id = aws_secretsmanager_secret.db.id   # which secret
  secret_string = jsonencode({                     # the value (JSON)
    username = "app"                              # the user
    password = random_password.db.result          # the random password
    host     = aws_db_instance.app.address        # the RDS endpoint
  })
}

data "aws_ami" "al2023" {                         # the base AMI
  most_recent = true                               # the latest
  owners      = ["amazon"]                         # from Amazon
  filter {                                        # AL2023 x86
    name   = "name"                               # by name
    values = ["al2023-ami-2023*-x86_64"]          # the pattern
  }
}

resource "aws_launch_template" "web" {            # the launch template (the recipe)
  name_prefix   = "web-lt-"                      # the name
  image_id      = data.aws_ami.al2023.id         # the AMI
  instance_type = "t4g.medium"                   # the size
  vpc_security_group_ids = [aws_security_group.web.id]   # the firewall (v5 LT uses vpc_security_group_ids)

  block_device_mappings {                          # an EBS root volume, ENCRYPTED (KMS)
    device_name = "/dev/xvda"                     # the device
    ebs {
      volume_size = 20                            # 20 GB
      encrypted   = true                          # encrypted at rest
      kms_key_id  = aws_kms_key.app.arn           # with the CMK
    }
  }

  # the bootstrap script
user_data = <<-EOF
    #!/bin/bash
    dnf install -y httpd
    systemctl enable --now httpd
    echo "app running on private tier" > /var/www/html/index.html
  EOF
}

resource "aws_lb" "web" {                         # the ALB (the public entry)
  name               = "web-alb"                  # the LB's name
  internal           = false                      # public
  load_balancer_type = "application"              # Layer 7
  security_groups    = [aws_security_group.alb.id]   # the ALB's SG
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]   # public subnets
}

resource "aws_security_group" "alb" {            # the ALB's SG
  name   = "alb-sg"                              # the group's name
  vpc_id = aws_vpc.main.id                       # which VPC

  ingress {                                      # HTTP from anywhere
    description = "HTTP"                         # a label
    from_port   = 80                           # the port
    to_port     = 80                           # the port
    protocol    = "tcp"                        # the protocol
    cidr_blocks = ["0.0.0.0/0"]                # anywhere
  }
  egress {                                       # allow out
    from_port   = 0                              # all ports
    to_port     = 0                              # all ports
    protocol    = "-1"                           # all protocols
    cidr_blocks = ["0.0.0.0/0"]                # anywhere
  }
}

resource "aws_lb_target_group" "web" {           # the target group (the instances)
  name              = "web-tg"                   # the TG's name
  port              = 80                         # the port
  protocol          = "HTTP"                     # the protocol
  vpc_id            = aws_vpc.main.id            # which VPC
  target_type       = "instance"                 # EC2 instances

  health_check {                                 # the health check
    path                = "/index.html"          # the path
    port                = "traffic-port"         # the instance's port
    healthy_threshold   = 2                      # 2 good = healthy
    unhealthy_threshold = 3                      # 3 bad = unhealthy
    timeout             = 5                      # the timeout
    interval            = 15                     # every 15s
    matcher             = "200"                  # expect 200
  }
}

resource "aws_lb_listener" "http" {              # the listener (port 80 → TG)
  load_balancer_arn = aws_lb.web.arn             # which ALB
  port              = 80                         # the port
  protocol          = "HTTP"                     # the protocol
  default_action {                                # route to the target group
    type             = "forward"                 # forward
    target_group_arn = aws_lb_target_group.web.arn   # to which TG
  }
}

resource "aws_autoscaling_group" "web" {         # the ASG (keep 1–3 instances)
  name                = "web-asg"                # the ASG's name
  launch_template {                               # which launch template
    id      = aws_launch_template.web.id         # the template
    version = "$Latest"                          # the latest version
  }
  min_size    = 1                                # never below 1
  max_size    = 3                                # never above 3
  desired_capacity = 2                           # start with 2
  vpc_zone_identifier = [aws_subnet.private_a.id, aws_subnet.private_b.id]   # the private subnets

  tag {                                           # a tag propagated to the instances
    key                 = "Tier"                 # the tag's key
    value               = "web"                  # the value
    propagate_at_launch = true                   # put it on the instances
  }
}

resource "aws_autoscaling_policy" "cpu" {        # the scaling policy (CPU 40%)
  name                   = "cpu-40"              # the policy's name
  policy_type            = "TargetTrackingScaling"   # target-tracking (the modern way)
  autoscaling_group_name = aws_autoscaling_group.web.name   # which ASG

  target_tracking_configuration {                 # the target-tracking settings
    predefined_metric_specification {             # a built-in metric
      predefined_metric_type = "ASGCPUUtilization"   # the metric (CPU)
    }
    target_value = 40                             # hold CPU at 40%
  }
}

resource "aws_db_subnet_group" "app" {           # the DB subnet group (≥2 AZs)
  name       = "prod-db-subnets"                 # the group's name
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]   # the private subnets
}

resource "aws_db_instance" "app" {               # the RDS MySQL instance
  identifier        = "prod-mysql"               # the identifier
  engine            = "mysql"                    # the engine
  engine_version    = "8.0"                      # the version
  instance_class    = "db.t4g.micro"             # the size (the cheapest)
  allocated_storage = 20                         # 20 GB
  db_name           = "appdb"                    # the initial database
  username          = "app"                      # the master user
  password          = random_password.db.result  # the master password (from Secrets Mgr)
  db_subnet_group_name   = aws_db_subnet_group.app.name   # the subnet group
  vpc_security_group_ids = [aws_security_group.rds.id]   # the firewall (v5: vpc_security_group_ids)
  storage_encrypted = true                       # encrypted at rest
  backup_retention_period = 7                    # 7 days of backups
  skip_final_snapshot = true                     # (lab: don't block destroy)
}

resource "aws_elasticache_subnet_group" "cache" {   # the cache subnet group
  name       = "prod-cache-subnets"               # the group's name
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]   # the subnets
}

resource "aws_elasticache_replication_group" "cache" {   # a single-node Redis
  replication_group_id = "prod-redis"            # the group's id
  description          = "prod single-node redis" # a description (required)
  node_type            = "cache.t4g.micro"      # the smallest node
  num_cache_clusters      = 1                       # 1 node
  engine               = "redis"                 # the engine
  engine_version        = "7.1"                  # the version
  parameter_group_name  = "default.redis7"       # the parameter group
  automatic_failover_enabled = false             # single node: no failover
  port                  = 6379                    # the port
  subnet_group_name     = aws_elasticache_subnet_group.cache.name   # the subnet group
  security_group_ids    = [aws_security_group.cache.id]   # the firewall
  at_rest_encryption_enabled = true              # encrypt at rest
  transit_encryption_enabled = true           # encrypt in transit
}

resource "aws_s3_bucket" "audit" {               # the audit bucket (locked)
  bucket = "prod-audit-${random_string.suffix.result}"   # a unique name
}

resource "random_string" "suffix" {              # a random suffix
  length  = 6                                    # 6 chars
  special = false                                # no special chars
}

resource "aws_s3_bucket_versioning" "audit" {    # versioning (the audit log is immutable)
  bucket = aws_s3_bucket.audit.id                # which bucket
  versioning_configuration { status = "Enabled" }   # on
}

resource "aws_s3_bucket_public_access_block" "audit" {   # block all public access
  bucket = aws_s3_bucket.audit.id                # which bucket
  block_public_acls       = true                 # block ACLs
  block_public_policy     = true                 # block policies
  ignore_public_acls      = true                 # ignore ACLs
  restrict_public_buckets = true                 # restrict public buckets
}

resource "aws_cloudtrail" "main" {               # the trail
  name                = "prod-trail"             # the trail's name
  s3_bucket_name      = aws_s3_bucket.audit.id   # where the logs go
  include_global_service_events = true           # include global (IAM) events
  is_multi_region_trail = true                   # trail in all regions

  event_selector {                                # log data events (S3/DynamoDB)
    read_write_type           = "All"             # all read+write
    include_management_events = true              # include management (API) events
  }
}

data "aws_iam_policy_document" "config_role" {    # the Config recorder role's trust doc
  statement {
    effect  = "Allow"                             # allow
    actions = ["sts:AssumeRole"]                  # the assume action
    principals {
      type        = "Service"                     # a service
      identifiers = ["config.amazonaws.com"]     # the Config service
    }
  }
}

resource "aws_iam_role" "config" {               # the Config recorder role
  name               = "config-recorder-role"    # the role's name
  assume_role_policy = data.aws_iam_policy_document.config_role.json   # the trust doc
}

resource "aws_iam_role_policy_attachment" "config" {   # the managed policy
  role       = aws_iam_role.config.id           # which role
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRole"   # the policy
}

resource "aws_config_configuration_recorder" "main" {   # the recorder
  name     = "prod-recorder"                    # the recorder's name
  role_arn = aws_iam_role.config.arn            # the role

  recording_group {                              # what to record
    all_supported = true                          # every supported resource type
    include_global_resource_types = true          # include global (IAM) resources (v5 name)
  }
}

resource "aws_config_delivery_channel" "main" {  # the delivery channel (→ S3)
  name           = "prod-channel"                # the channel's name
  s3_bucket_name = aws_s3_bucket.audit.id        # which bucket
  depends_on     = [aws_iam_role_policy_attachment.config]   # wait for the policy
}

resource "aws_config_config_rule" "encrypted" {  # a compliance rule
  name = "encrypted-volumes"                     # the rule's name

  source {                                        # the built-in rule
    owner             = "AWS"                     # AWS-managed
    source_identifier = "ENCRYPTED_VOLUMES_AT_REST"   # EBS must be encrypted
  }

  input_parameters = jsonencode({ encrypted = "true" })   # the rule's parameters (v5: a JSON string)
}

resource "aws_route53_zone" "lab" {              # the hosted zone (CHANGE the domain)
  name = "lab-example.com"                       # the domain (you must own this to use it)
}

resource "aws_route53_record" "www" {            # the A record (alias to the ALB)
  zone_id = aws_route53_zone.lab.zone_id         # which zone
  name    = "www"                                # the record's name (www.lab-example.com)
  type    = "A"                                  # an A record
  alias {                                        # an ALIAS (no extra charge, no TTL)
    name                   = aws_lb.web.dns_name  # the ALB's DNS name
    zone_id                = aws_lb.web.zone_id   # the ALB's zone id
    evaluate_target_health = true                 # follow the ALB's target health
  }
}

resource "aws_cloudfront_distribution" "web" {   # the CloudFront distribution
  origin {                                        # the origin (the ALB)
    domain_name = aws_lb.web.dns_name            # the ALB's DNS name
    origin_id   = "alb"                          # the origin's id
  }

  enabled             = true                     # on
  default_root_object = "index.html"             # the default object

  default_cache_behavior {                        # the default caching behavior
    allowed_methods        = ["GET", "HEAD"]     # the methods
    cached_methods         = ["GET", "HEAD"]     # the methods to cache
    target_origin_id       = "alb"               # which origin
    viewer_protocol_policy = "redirect-to-https" # force HTTPS
    compress               = true                # compress
  }

  restrictions {                                    # geo restrictions (none)
    geo_restriction {
      restriction_type = "none"                     # no geo restriction
    }
  }

  viewer_certificate {                              # the viewer certificate (required in v5)
    cloudfront_default_certificate = true            # use the CloudFront default (wildcard) cert
  }

  price_class = "PriceClass_100"                 # edge locations worldwide
}
