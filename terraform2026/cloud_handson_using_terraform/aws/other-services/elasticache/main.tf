# ============================================================================
#  ElastiCache — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_vpc" "main" {                      # the VPC
  cidr_block = "10.0.0.0/16"                     # the space
}

resource "aws_subnet" "a" {                      # subnet A
  vpc_id            = aws_vpc.main.id            # which VPC
  cidr_block        = "10.0.1.0/24"              # inside
  availability_zone = "us-east-1a"               # AZ a
}

resource "aws_subnet" "b" {                      # subnet B (≥2 AZs for HA)
  vpc_id            = aws_vpc.main.id            # which VPC
  cidr_block        = "10.0.2.0/24"              # inside
  availability_zone = "us-east-1b"               # AZ b
}

resource "aws_elasticache_subnet_group" "cache" {   # the subnet group
  name       = "lab-cache-subnet-group"           # the group's name
  subnet_ids = [aws_subnet.a.id, aws_subnet.b.id] # which subnets (≥2 AZs)
}

resource "aws_security_group" "cache" {          # the cache's firewall (allow only the app)
  name   = "lab-redis"                          # the group's name
  vpc_id = aws_vpc.main.id                       # which VPC

  ingress {                                      # from the APP group only
    description = "from the app"                # a label
    from_port   = 6379                         # the Redis port
    to_port     = 6379                         # the same
    protocol    = "tcp"                        # TCP
    security_groups = [aws_security_group.app.id]   # the app's group (not 0.0.0.0/0)
  }
}

resource "aws_security_group" "app" {            # the app's firewall
  name   = "lab-app"                            # the group's name
  vpc_id = aws_vpc.main.id                       # which VPC

  # the app's outbound to the cache is allowed by the cache's ingress above.
}

resource "aws_elasticache_replication_group" "redis" {   # a replication group (even single node)
  replication_group_id = "lab-redis"            # the group's id (also the endpoint prefix)
  description          = "lab single-node redis"   # a description
  node_type            = "cache.t4g.micro"      # the smallest node (Free Tier eligible)
  num_cache_clusters      = 1                       # 1 primary (no replica)
  engine               = "redis"                 # the engine
  engine_version        = "7.1"                  # the version
  parameter_group_name  = "default.redis7"       # the parameter group
  port                  = 6379                    # the port
  subnet_group_name     = aws_elasticache_subnet_group.cache.name   # the subnet group (required)
  security_group_ids    = [aws_security_group.cache.id]   # the firewall
  automatic_failover_enabled = false             # single node: no failover (true + a replica = HA)
  at_rest_encryption_enabled = true              # encrypt at rest (KMS default key)
  transit_encryption_enabled = true           # encrypt in transit (TLS)
}
