# ============================================================================
#  KMS — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_kms_key" "app" {                   # the CMK
  description             = "lab app encryption key"   # a description
  enable_key_rotation     = true                 # auto-rotate yearly
  deletion_window_in_days = 7                    # 7-day deletion window (7-30)
  tags                    = { env = "lab" }      # a label
}

data "aws_iam_policy_document" "key_policy" {     # the key policy document
  statement {
    sid    = "AllowUse"                          # the statement's id
    effect = "Allow"                             # allow
    actions = [                                  # the service-level actions
      "kms:Encrypt",                             # encrypt
      "kms:Decrypt",                             # decrypt
      "kms:ReEncrypt*",                          # re-encrypt (rotation)
      "kms:GenerateDataKey*",                    # data keys (how S3/EBS use the key)
    ]
    principals {                                 # who
      type        = "AWS"                        # an IAM principal
      identifiers = [aws_iam_role.worker.arn]   # the worker role
    }
  }

  statement {
    sid    = "AllowManage"                       # the management statement
    effect = "Allow"                             # allow
    actions = [                                   # management actions
      "kms:Create*",                             # create
      "kms:Describe*",                           # describe
      "kms:Get*",                                # get
      "kms:List*",                               # list
      "kms:Enable*",                             # enable
      "kms:Disable*",                            # disable
      "kms:Delete*",                             # delete
      "kms:Put*",                                # put
      "kms:Update*",                             # update
      "kms:TagResource",                         # tag
      "kms:UntagResource",                       # untag
    ]
    principals {
      type        = "AWS"                        # an IAM principal
      identifiers = [data.aws_caller_identity.current.arn]   # YOU (the account admin)
    }
  }
}

data "aws_caller_identity" "current" {}           # the current caller's identity

resource "aws_kms_key_policy" "app" {             # attach the key policy
  key_id = aws_kms_key.app.id                    # which key
  policy = data.aws_iam_policy_document.key_policy.json   # the policy JSON
}

resource "aws_iam_role" "worker" {                # a role that will use the key
  name     = "lab-worker"                         # the role's name

  assume_role_policy = jsonencode({               # the trust document
    Version = "2012-10-17"                         # the version
    Statement = [{                                 # one statement
      Effect    = "Allow"                          # allow
      Action    = "sts:AssumeRole"                 # the assume action
      Principal = { Service = "lambda.amazonaws.com" }   # assumed by Lambda
    }]
  })
}

resource "aws_kms_alias" "app" {                  # the alias
  name          = "alias/lab-app"                 # the alias name (arn:alias/lab-app)
  target_key_id = aws_kms_key.app.key_id          # which key
}

resource "aws_s3_bucket" "secrets" {              # a bucket
  bucket = "lab-kms-secrets-${random_string.suffix.result}"   # a unique name
}

resource "random_string" "suffix" {               # the random suffix
  length  = 6                                    # 6 chars
  special = false                                # no special chars (S3 names)
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sse" {   # encrypt objects with the key
  bucket = aws_s3_bucket.secrets.id              # which bucket

  rule {                                          # the encryption rule
    apply_server_side_encryption_by_default {     # SSE by default
      sse_algorithm     = "aws:kms"               # KMS (vs AES256 = AWS-managed)
      kms_master_key_id = aws_kms_key.app.arn     # WHICH key
    }
  }
}
