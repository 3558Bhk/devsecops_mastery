# AWS 6 — Databases (RDS, Aurora, DynamoDB)

> **⏱️ Time to complete: ~75 min** (read + spin up an RDS instance + a DynamoDB table)

## 6.1 RDS — Managed Relational DB (the pattern)

```hcl
# Subnet group (DB subnets = private, isolated, multi-AZ)
resource "aws_db_subnet_group" "main" {     # a DB subnet group
  name       = "${local.name_prefix}-db"   # the group name
  subnet_ids = module.vpc.private_subnet_ids   # the (private) subnets
  tags       = { Name = "${local.name_prefix}-db-subnets" }
}

# Security group: only the web tier may reach the DB
resource "aws_security_group" "db" {        # a security group for the DB
  name_prefix = "${local.name_prefix}-db-"  # name prefix
  vpc_id      = aws_vpc.main.id             # the VPC

  ingress {                                  # an inbound rule
    description = "postgres from web tier"   # what it does
    from_port   = 5432                       # postgres port
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [aws_security_group.web.id]   # only from the web SG
  }
  egress {                                   # outbound
    from_port = 0
    to_port   = 0
    protocol  = "-1"                         # all protocols
    cidr_blocks = ["0.0.0.0/0"]   # (restrict to S3/patching if you want)
  }
  tags = { Name = "${local.name_prefix}-db-sg" }
}

# Secrets: generate + store (never hardcode)
resource "random_password" "db" {           # generate a strong password
  length  = 20                              # 20 chars
  special = false                           # no special chars (DB-friendly)
}

resource "aws_secretsmanager_secret" "db" {   # a Secrets Manager secret
  name = "${local.name_prefix}/db"            # the secret name
}

resource "aws_secretsmanager_secret_version" "db" {   # the secret's value
  secret_id = aws_secretsmanager_secret.db.id   # the secret
  secret_string = jsonencode({                 # the secret payload
    username = "appadmin"                      # the DB user
    password = random_password.db.result       # the generated password
    host     = "pending"   # (updated post-apply; or read via data source)
    port     = 5432                            # the port
    dbname   = "app"                           # the database name
  })
}

data "aws_rds_engine_version" "pg" {        # find the engine version
  engine             = "postgres"           # the engine
  latest_version     = true                 # the latest
  # engine_version = "16.*"   # (or pin a major)
}

resource "aws_db_instance" "main" {         # the RDS instance
  identifier     = "${local.name_prefix}-db"   # a unique identifier
  engine         = "postgres"                  # the engine
  engine_version = data.aws_rds_engine_version.pg.version   # the version
  instance_class = var.environment == "prod" ? "db.m6i.large" : "db.t4g.micro"   # size by env

  allocated_storage     = 100                  # 100 GB
  max_allocated_storage = 400          # auto-grow (stop the disk-full 3am)
  storage_type          = "gp3"                 # gp3
  storage_encrypted     = true                  # encrypt
  kms_key_id            = aws_kms_key.db.arn    # the CMK

  db_name  = "app"                              # the database name
  username = "appadmin"                         # the master user
  password = random_password.db.result          # the master password

  db_subnet_group_name   = aws_db_subnet_group.main.name   # the subnet group
  vpc_security_group_ids = [aws_security_group.db.id]      # the SG
  multi_az               = (var.environment == "prod")   # standby in 2nd AZ (prod)
  publicly_accessible    = false                 # never public
  backup_retention_period = 7                    # 7 days of automated backups
  deletion_protection    = (var.environment == "prod")   # block delete (prod)
  skip_final_snapshot    = (var.environment != "prod")   # skip snapshot (dev)
  final_snapshot_identifier = (var.environment == "prod") ? null : "${local.name_prefix}-db-final"

  performance_insights_enabled = (var.environment == "prod")   # query metrics (prod)

  tags = { Name = "${local.name_prefix}-db" }  # tag

  lifecycle {                                  # lifecycle
    prevent_destroy = (var.environment == "prod")   # protect prod
  }
}

# Allow connections from the web tier only (already enforced by SG)
```

### RDS knobs that matter

| Knob | Meaning |
|---|---|
| `instance_class` | `db.t4g.micro` (dev) → `db.m6i.large`+ (prod); `db.r*` for memory |
| `multi_az` | Synchronous standby in a 2nd AZ (HA, ~2× cost) |
| `allocated_storage` + `max_allocated_storage` | Auto-scaling storage (gp3/io1) |
| `storage_encrypted` | EBS-level encryption (can't disable later) |
| `backup_retention_period` | Automated backups (0–35 days) |
| `deletion_protection` | Block `terraform destroy`/console delete (prod) |
| `skip_final_snapshot` | Don't snapshot on delete (dev); **prod must NOT skip** |
| `performance_insights` | Query-level metrics (long-term retention costs) |
| `parameter_group` | Engine tuning (timeouts, buffers) |
| `engine_version` | Pin major; `latest_version = true` for minor |

### Parameter group

```hcl
resource "aws_db_parameter_group" "pg" {     # a parameter group
  name   = "${local.name_prefix}-pg"         # the group name
  family = "postgres16"                       # the engine family
  parameter { name = "log_min_duration_statement"; value = "250" }   # log slow queries (ms)
  parameter { name = "track_io_timing"; value = "on" }   # track IO timing
}
# reference it: parameter_group_name = aws_db_parameter_group.pg.name
```

## 6.2 Aurora (managed, scalable, Postgres/MySQL compatible)

```hcl
resource "aws_rds_cluster" "aurora" {        # an Aurora cluster
  cluster_identifier  = "${local.name_prefix}-aurora"   # unique id
  engine              = "aurora-postgresql"  # the engine
  engine_version      = "16.1"          # (verify current)
  database_name       = "app"            # the initial database
  master_username     = "appadmin"       # the master user
  master_password     = random_password.db.result   # the master password
  db_subnet_group_name = aws_db_subnet_group.main.name   # the subnet group
  vpc_security_group_ids = [aws_security_group.db.id]   # the SG
  storage_encrypted   = true              # encrypt
  backup_retention_period = 7             # 7 days
  deletion_protection  = (var.environment == "prod")   # protect (prod)

  # Serverless v2 (scales 0.5–32 ACUs; great for variable load)
  serverlessv2_scaling_configuration {     # serverless v2 settings
    min_capacity = 0.5                     # minimum ACUs
    max_capacity = 8                       # maximum ACUs
  }

  tags = { Name = "${local.name_prefix}-aurora" }
}

# Reader endpoints scale out automatically
resource "aws_rds_cluster_instance" "aurora" {   # a cluster instance (reader)
  count              = var.aurora_readers   # e.g. 2 (via count)
  identifier         = "${local.name_prefix}-aurora-r${count.index}"   # unique id
  cluster_identifier = aws_rds_cluster.aurora.id   # the cluster
  instance_class     = "db.r6g.large"       # the size
  promote_on_write_upgrade = true           # promote on write upgrade
  publicly_accessible  = false              # never public
  skip_final_snapshot  = (var.environment != "prod")   # skip snapshot (dev)
}
```

- Aurora = **storage decoupled** (scales to 128 TiB), **multiple reader endpoints**, **Postgres/MySQL wire-compatible**.
- Connect to the **cluster endpoint** (writer) or **reader endpoint** (load-balanced readers).

## 6.3 DynamoDB (managed NoSQL)

```hcl
resource "aws_dynamodb_table" "orders" {     # a DynamoDB table
  name         = "${local.name_prefix}-orders"   # the table name
  billing_mode = "PAY_PER_REQUEST"     # on-demand (no capacity math)
  hash_key     = "order_id"           # the partition key
  range_key    = "created_at"           # the sort key

  attribute { name = "order_id";   type = "S" }   # declare the hash key attribute (String)
  attribute { name = "created_at"; type = "S" }   # declare the range key attribute

  global_secondary_index {               # a GSI
    name            = "ByCustomer"       # the index name
    projection_type = "ALL"              # project all attributes
    hash_key        = "customer_id"      # the index key
    attribute { name = "customer_id"; type = "S" }   # declare the index attribute
  }

  point_in_time_recovery { enabled = true }   # continuous backups
  stream_enabled         = true               # for triggers / replication
  stream_view_type       = "NEW_AND_OLD_IMAGES"

  ttl {
    attribute_name = "expires_at"   # the attribute holding an epoch for TTL
  }

  tags = { Name = "${local.name_prefix}-orders" }
}
```

- **`PAY_PER_REQUEST`** = on-demand; **PROVISIONED** = explicit RCU/WCU (cost control at high steady load).
- **GSI** = secondary index (its own keys + projection). **LSI** = only one, shares the table's write capacity.
- **TTL** = automatic expiry (store an epoch `expires_at`).
- **Streams** + **DynamoDB Global Tables** (multi-region replication).

## 6.4 Choosing the Database

| Need | Pick |
|---|---|
| Standard relational, HA | **RDS** (Postgres/MySQL) |
| High read scale, Postgres/MySQL compat, storage >16TB | **Aurora** |
| Massive scale, low latency, key-value/document | **DynamoDB** |
| Analytical / OLAP | **Redshift** |
| Search | **OpenSearch** |
| Cache | **ElastiCache** (Redis/Memcached) |

## 6.5 Getting It Right / Gotchas

- **DB subnets must be in ≥2 AZs** (for `multi_az`).
- **Never** `publicly_accessible = true` in prod.
- **Secrets**: generate with `random_password`, store in Secrets Manager; DB `password` arg is fine (it's in state — rotate + `sensitive`).
- **`deletion_protection` + `prevent_destroy`** on prod DBs (double safety).
- **`skip_final_snapshot = false`** in prod (keep the last snapshot).
- **`max_allocated_storage`** to avoid disk-full outages.
- **Pin `engine_version` major** (avoid silent major upgrades).
- **Aurora** = cluster (storage) + instances (writers/readers); connect via **cluster endpoint**.
- **DynamoDB** `billing_mode` + `point_in_time_recovery` + `stream` are the "production" trio.
- Changing `engine` or `instance_class` in a way that can't be done in-place → **replace** (downtime) — plan for it.

## 6.6 Interview Quick Facts

- **RDS** = managed relational (single writer + optional Multi-AZ standby).
- **Aurora** = decoupled storage, reader scaling, Postgres/MySQL compatible.
- **`multi_az`** = synchronous standby in a 2nd AZ (HA, ~2×).
- **DynamoDB** = key-value/document, `hash_key` (+ optional `range_key`), GSI/LSI, TTL, PITR, streams.
- **DB subnets** = private, isolated, multi-AZ.
- **Secrets** via Secrets Manager; **encryption** on; **deletion protection** in prod.
- `PAY_PER_REQUEST` (on-demand) vs `PROVISIONED` (capacity units).
