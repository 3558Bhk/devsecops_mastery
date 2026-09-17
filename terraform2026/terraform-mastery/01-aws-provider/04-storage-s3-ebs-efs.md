# AWS 4 — Storage (S3, EBS, EFS)

> **⏱️ Time to complete: ~50 min** (read + create the complete S3 bucket pattern)

## 4.1 S3 — The Complete Bucket (the pattern)

```hcl
resource "aws_s3_bucket" "app" {            # the bucket itself
  bucket        = "${local.name_prefix}-app-${data.aws_region.current.name}"   # unique name
  force_destroy = (var.environment != "prod")   # dev-only safety valve (delete objects on destroy)
}

# Versioning (irreversible once enabled; protects against accidental delete)
resource "aws_s3_bucket_versioning" "app" {   # versioning on the bucket
  bucket = aws_s3_bucket.app.id               # target the bucket
  versioning_configuration {                  # the versioning settings
    status = "Enabled"                        # turn versioning ON
    # multipart_failures = "Enabled"
  }
}

# Server-side encryption (KMS + bucket key = cheaper)
resource "aws_s3_bucket_server_side_encryption_configuration" "app" {  # SSE
  bucket = aws_s3_bucket.app.id               # target the bucket
  rule {                                      # one encryption rule
    apply_server_side_encryption_by_default { # default encryption on upload
      sse_algorithm     = "aws:kms"           # encrypt with KMS
      kms_master_key_id = aws_kms_key.s3.arn  # the specific CMK
    }
    bucket_key_enabled = true                 # a bucket key (cheaper KMS calls)
  }
}

# Block ALL public access (default should be fully on)
resource "aws_s3_bucket_public_access_block" "app" {   # the public access block
  bucket                  = aws_s3_bucket.app.id   # target the bucket
  block_public_acls       = true   # no public ACLs
  block_public_policy     = true   # no public bucket policy
  ignore_public_acls      = true   # ignore public object ACLs
  restrict_public_buckets = true   # fail if the bucket is public
}

# Lifecycle: tier to cheaper classes, expire old objects
resource "aws_s3_bucket_lifecycle_configuration" "app" {  # lifecycle config
  bucket = aws_s3_bucket.app.id               # target the bucket
  rule {                                      # one lifecycle rule
    id     = "tiering"                        # rule id (unique in the bucket)
    status = "Enabled"                        # active
    filter { prefix = "logs/" }               # apply to objects under logs/
    transition {                              # first transition
      days          = 30                      # after 30 days
      storage_class = "STANDARD_IA"           # to Infrequent Access
    }
    transition {                              # second transition
      days          = 90                      # after 90 days
      storage_class = "GLACIER"               # to Glacier
    }
    expiration { days = 365 }                 # delete after 365 days
    noncurrent_version_expiration {           # expire old versions
      noncurrent_days = 30                    # after 30 days non-current
    }
  }
}

# Access logging (to a separate bucket)
resource "aws_s3_bucket_logging" "app" {      # access logs
  bucket = aws_s3_bucket.app.id               # the source bucket
  target_bucket = aws_s3_bucket.logs.id       # where logs go
  target_prefix = "app/"                      # the log object prefix
}
```

### The big idea: **one bucket = many small resources**

S3's attributes live in **separate resources**: `aws_s3_bucket_versioning`, `_lifecycle_configuration`, `_website_configuration`, `_policy`, `_replication_configuration`, `_cors_configuration`, `_acceleration`, `_ownership_controls`, `_object_lock_configuration`, `_intelligent_tiering_configuration`. This is deliberate — each can be managed/permissioned independently.

### Bucket Policy (cross-account / specific grants)

```hcl
data "aws_iam_policy_document" "s3_read" {    # build an IAM-style policy doc
  statement {                                  # one statement
    sid    = "AllowReadFromSpecificAccount"   # a statement id
    effect = "Allow"                          # allow
    actions = [                                # the permitted actions
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [                              # the resources
      aws_s3_bucket.app.arn,                   # the bucket
      "${aws_s3_bucket.app.arn}/*",            # and its objects
    ]
    principals {                               # who may do it
      type        = "AWS"                      # an AWS principal
      identifiers = ["arn:aws:iam::222222222222:root"]   # that account
    }
  }
}

resource "aws_s3_bucket_policy" "app" {       # attach the policy to the bucket
  bucket = aws_s3_bucket.app.id               # target the bucket
  policy = data.aws_iam_policy_document.s3_read.json   # the policy JSON
}
```

### Static website hosting

```hcl
resource "aws_s3_bucket_website_configuration" "site" {   # static website
  bucket = aws_s3_bucket.app.id               # target the bucket
  index_document { suffix = "index.html" }    # the index document
  error_document { key   = "error.html" }     # the error document
  # redirect_all_requests_to { host_name = "example.com" }
}
```
(For prod, put **CloudFront** in front — see AWS 09 — and keep the bucket private.)

## 4.2 S3 Storage Classes & Replication

| Class | Use |
|---|---|
| `STANDARD` | Frequently accessed |
| `STANDARD_IA` | Infrequent access (30-day min) |
| `ONEZONE_IA` | Infrequent, single-AZ (cheaper) |
| `GLACIER` / `GLACIER_IR` | Archive |
| `DEEP_ARCHIVE` | Cold archive (cheapest, retrieval hours–days) |

**Cross-region replication (CRR)** — DR + compliance:

```hcl
resource "aws_s3_bucket" "dr" {
  bucket = "${local.name_prefix}-app-dr"      # the DR bucket name
  region = "eu-west-1"                        # the DR region
}

resource "aws_iam_role" "replication" {       # the replication role
  name = "s3-replication-${local.name_prefix}"   # role name
  assume_role_policy = jsonencode({           # the trust policy
    Version = "2012-10-17"                     # IAM policy version
    Statement = [{                             # one statement
      Effect = "Allow"                         # allow
      Action = "sts:AssumeRole"                # assume-role
      Principal = { Service = "s3.amazonaws.com" }  # trusted by S3
    }]
  })
}

resource "aws_s3_bucket_replication_configuration" "app" {   # the replication config
  role = aws_iam_role.replication.arn         # the replication role
  rule {                                      # one replication rule
    id     = "to-dr"                          # rule id
    status = "Enabled"                        # active
    destination {                              # where to replicate
      bucket        = aws_s3_bucket.dr.arn    # the DR bucket
      storage_class = "STANDARD"              # the storage class
    }
  }
}
```
Requirements: versioning on **both** buckets, a dedicated IAM role, (optionally) **Object Ownership = BucketOwnerEnforced**.

## 4.3 EBS (block storage, instance-attached)

```hcl
resource "aws_ebs_volume" "data" {            # an EBS volume
  availability_zone = "ap-south-1a"           # EBS is single-AZ
  size              = 100                     # 100 GB
  type              = "gp3"                   # gp3
  encrypted         = true                    # encrypted
  iops              = 3000                    # IOPS
  throughput        = 125                     # MB/s
  tags              = { Name = "data" }       # tag
}

resource "aws_volume_attachment" "data" {     # attach the volume to an instance
  device_name = "/dev/sdf"                    # the device name
  volume_id   = aws_ebs_volume.data.id        # the volume
  instance_id = aws_instance.web.id           # the instance
  stop_instance_before_detaching = false      # don't stop the instance on detach
}

# Snapshot (backup / AMI source)
resource "aws_ebs_snapshot" "backup" {        # a snapshot of the volume
  volume_id = aws_ebs_volume.data.id          # the source volume
  tags      = { Name = "daily" }              # tag
  # kms_key_id = aws_kms_key.ebs.arn          # (optional) encrypt with a CMK
}
```

- EBS is **single-AZ** (tied to an AZ). For cross-AZ, snapshot + restore.
- `gp3` default (3000 IOPS/125 MBps baseline); `io2`/`io2_block` for high IOPS; `st1`/`sc1` for cheap throughput.

## 4.4 EFS (shared file system, NFS, multi-AZ)

```hcl
resource "aws_efs_file_system" "shared" {     # an EFS file system
  creation_token = "${local.name_prefix}-efs"   # must be unique
  encrypted      = true                        # encrypted
  kms_key_id     = aws_kms_key.ebs.arn         # the CMK
  throughput_mode = "bursting"   # or "elastic"
  performance_mode = "generalPurpose"
  lifecycle_policy = "after_7_days"   # auto-tier to Infrequent after 7 days

  tags = { Name = "shared" }              # tag
}

# One mount target PER AZ (min 2 for HA)
resource "aws_efs_mount_target" "mt" {       # a mount target (one per AZ via count)
  count = length(local.azs)                 # one per AZ
  file_system_id = aws_efs_file_system.shared.id   # the file system
  subnet_id      = aws_subnet.private[count.index].id   # the subnet
  security_groups = [aws_security_group.efs.id]   # NFS = 2049 tcp
}

# Access point (POSIX identity per app)
resource "aws_efs_access_point" "app" {      # an access point
  file_system_id  = aws_efs_file_system.shared.id   # the file system
  root_directory  = { path = "/app", creation_info = { owner_uid = 1000, owner_gid = 1000, mode = "0755" } }   # the root
  posix_user      = { uid = 1000, gid = 1000 }   # the POSIX identity
}
```

- **S3** = objects (HTTP), infinite, cheap, global. **EBS** = block (1 instance, 1 AZ). **EFS** = file (NFS, multi-instance, multi-AZ).
- EFS is **multi-AZ** (mount targets in multiple AZs); EBS is not.

## 4.5 Choosing the Right Storage

| Need | Service |
|---|---|
| Web assets, logs, backups, data lake | **S3** |
| Fast local disk for 1 instance (DB, cache) | **EBS** (or instance store) |
| Shared file system (NFS) across instances | **EFS** |
| Shared SMB (Windows) | **FSx for Windows** |
| High-throughput shared (HPC) | **FSx for Lustre** / **EFS Max** |
| Object, cross-region | **S3** (+ CRR) |

## 4.6 KMS (encryption keys) — you'll reference it everywhere

```hcl
resource "aws_kms_key" "s3" {                # a KMS customer master key
  description             = "S3 bucket encryption"   # description
  deletion_window_in_days = 30               # must wait 30 days before the key is deleted
  enable_key_rotation     = true             # auto-rotate annually
  tags                    = { Name = "s3-key" }   # tag
}

resource "aws_kms_alias" "s3" {              # a friendly alias for the key
  name = "alias/${local.name_prefix}-s3"     # the alias name
  target_key_id = aws_kms_key.s3.key_id      # the key it points to
}
```
`deletion_window_in_days` (7–30) means `terraform destroy` **waits** that long before the key is actually deletable — plan your teardown.

## 4.7 Getting It Right

- **Public access block = all true** (default posture). Public buckets = policy grants, not ACLs.
- **Versioning + lifecycle** on any bucket holding important data.
- **SSE-KMS** for prod; `bucket_key_enabled = true` to cut KMS costs.
- **`force_destroy`** only in dev (it deletes objects — dangerous).
- **Replication** needs a dedicated role + versioning on both sides.
- **S3 is not strongly consistent for list?** — it is now (strong read-after-write since 2020). Don't assume old caveats.

## 4.8 Interview Quick Facts

- S3 attributes = **separate resources** (versioning, lifecycle, policy, website, replication).
- **S3 vs EBS vs EFS**: object/global vs block/1-AZ vs file/multi-AZ.
- **CRR** = cross-region DR; needs versioning + a dedicated role.
- **Public access block** is the modern "is it public?" switch (4 flags, all on).
- **KMS** with `enable_key_rotation` + `deletion_window_in_days` (teardown delay).
- **gp3** is the default EBS; **io2** for IOPS; **st1/sc1** for cheap throughput.
