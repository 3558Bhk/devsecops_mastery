# ============================================================================
#  AWS Config — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

data "aws_iam_policy_document" "config_assume" {  # who may assume the recorder role
  statement {
    effect  = "Allow"                             # allow
    actions = ["sts:AssumeRole"]                  # the assume action
    principals {                                    # by whom:
      type        = "Service"                     # a service
      identifiers = ["config.amazonaws.com"]     # AWS Config
    }
  }
}

resource "aws_iam_role" "config" {               # the role AWS Config uses
  name               = "lab-config-role"         # the role's name
  assume_role_policy = data.aws_iam_policy_document.config_assume.json   # the trust document
}

resource "aws_iam_role_policy_attachment" "managed" {   # the managed policy that grants Config what it needs
  role       = aws_iam_role.config.id            # which role
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRole"   # AWS's built-in Config policy
}

resource "aws_config_configuration_recorder" "lab" {   # the recorder
  name     = "lab-recorder"                      # the recorder's name
  role_arn = aws_iam_role.config.arn             # the role it uses

  recording_group {                               # what to record
    all_supported = true                          # every supported resource type
  }
}

resource "aws_config_configuration_recorder_status" "lab" {   # and START it
  name = aws_config_configuration_recorder.lab.name   # which recorder
  is_enabled = true                             # start recording
}

resource "aws_s3_bucket" "config" {              # the bucket the delivery writes to
  bucket = "config-lab-2026"                     # the GLOBAL name
}

resource "aws_s3_bucket_public_access_block" "config" {   # never public
  bucket                  = aws_s3_bucket.config.id   # which bucket
  block_public_acls       = true                     # no public ACLs
  block_public_policy     = true                     # no public policies
  ignore_public_acls      = true                     # strip public ACLs
  restrict_public_buckets = true                     # public only if explicitly asked
}

resource "aws_s3_bucket_policy" "config" {       # let ONLY the config service write here
  bucket = aws_s3_bucket.config.id               # which bucket

  policy = jsonencode({                          # the policy JSON
    Version = "2012-10-17"                        # the version
    Statement = [{                                 # one statement
      Sid       = "AllowConfigDelivery"            # an id
      Effect    = "Allow"                          # allow
      Principal = { Service = "config.amazonaws.com" }  # by the Config service
      Action    = "s3:PutObject"                   # writing the snapshot files
      Resource  = "${aws_s3_bucket.config.arn}/*"  # in this bucket
    }]
  })
}

resource "aws_config_delivery_channel" "lab" {   # the delivery channel (the modern resource)
  name             = "lab-delivery"              # the channel's name
  s3_bucket_name   = aws_s3_bucket.config.id    # the destination bucket

  snapshot_delivery_properties {                   # full snapshots
    delivery_frequency = "TwentyFour_Hours"                    # once a day (the only choice for snapshots)
  }
}

resource "aws_config_config_rule" "ebs_encrypted" {   # the compliance rule
  name        = "ebs-volumes-encrypted"             # the rule's name
  description = "EBS volumes must be encrypted"     # a human note

  source {                                          # which rule engine
    owner             = "AWS"                       # a managed rule (vs "CUSTOM" = your Lambda)
    source_identifier = "ENCRYPTED_VOLUMES_AT_REST" # the built-in rule: EBS encryption
  }

  # scope: (leave off = all EBS volumes; you can limit to resource types/tags)
}
