# ============================================================================
#  CloudTrail — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_s3_bucket" "trail" {               # the bucket the trail writes to
  bucket = "trail-lab-2026"                      # the GLOBAL name (must be unique)
}

resource "aws_s3_bucket_public_access_block" "trail" {   # audit logs are never public
  bucket                  = aws_s3_bucket.trail.id   # which bucket
  block_public_acls       = true                     # no public ACLs
  block_public_policy     = true                     # no public policies
  ignore_public_acls      = true                     # strip public ACLs
  restrict_public_buckets = true                     # public only if explicitly asked
}

resource "aws_s3_bucket_versioning" "trail" {    # version the audit logs (tamper-evidence)
  bucket = aws_s3_bucket.trail.id               # which bucket
  versioning_configuration {
    status = "Enabled"                            # on
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {   # encrypt the logs
  bucket = aws_s3_bucket.trail.id               # which bucket
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"                   # KMS encryption
    }
  }
}

resource "aws_cloudtrail" "lab" {                # the trail
  name             = "lab-trail"                  # the trail's name
  s3_bucket_name   = aws_s3_bucket.trail.id      # where the log files go
  is_multi_region_trail = true                    # record events from ALL regions
  include_global_service_events = true            # also record global events (IAM, Route 53)
  enable_logging   = true                         # the trail is live

  event_selector {                                 # WHAT to record
    read_write_type            = "All"             # both reads and writes (events)
    include_management_events  = true              # the API management events (the default audit set)
  }
}
