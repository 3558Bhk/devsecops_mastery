# ============================================================================
#  S3 Bucket — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_s3_bucket" "lab" {                 # the bucket itself
  bucket = "lab-bucket-2026"                     # the GLOBAL name (unique across all of AWS)
}

resource "aws_s3_bucket_versioning" "lab" {      # versioning: every overwrite keeps the old object
  bucket = aws_s3_bucket.lab.id                  # which bucket
  versioning_configuration {                      # the versioning state
    status = "Enabled"                            # Enabled | Suspended
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lab" {   # encrypt at rest
  bucket = aws_s3_bucket.lab.id                  # which bucket

  rule {                                          # the encryption rule
    apply_server_side_encryption_by_default {     # what to do by default
      sse_algorithm = "aws:kms"                   # KMS (vs AES256 = S3-managed key)
    }
  }
}

resource "aws_s3_bucket_public_access_block" "lab" {   # the 4 locks: NO public access, ever
  bucket = aws_s3_bucket.lab.id                  # which bucket
  block_public_acls       = true                 # 1: block public ACLs
  block_public_policy     = true                 # 2: block public bucket policies
  ignore_public_acls      = true                 # 3: ignore public ACLs on objects
  restrict_public_buckets = true                 # 4: public only if explicitly configured
}

resource "aws_s3_bucket_lifecycle_configuration" "lab" {   # age objects into cheaper storage
  bucket = aws_s3_bucket.lab.id                  # which bucket

  rule {                                          # rule 1: move old objects to Infrequent Access
    id     = "to-ia"                              # the rule's id
    status = "Enabled"                            # on

    transition {                                  # the move
      days          = 30                           # after 30 days
      storage_class = "STANDARD_IA"               # to Infrequent Access (cheaper storage)
    }
  }

  rule {                                          # rule 2: clean up old versions
    id     = "cleanup-versions"                   # the rule's id
    status = "Enabled"                            # on

    noncurrent_version_expiration {               # non-current versions (overwrites)
      noncurrent_days = 7                          # expire after 7 days as non-current
    }
  }
}

resource "aws_s3_bucket_logging" "lab" {         # access logging (audit: who got what)
  bucket                    = aws_s3_bucket.lab.id   # which bucket is being logged
  target_bucket             = aws_s3_bucket.lab.id   # where the logs go (same bucket for the lab)
  target_prefix             = "access-logs/"         # the log prefix

  depends_on = [aws_s3_bucket_public_access_block.lab]   # logging needs the bucket locked down first
}
