# ============================================================================
#  IAM Policies (managed) — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

data "aws_caller_identity" "current" {           # data block: our own account id (for ARNs)
  # no arguments — returns the account the provider is logged in as
}

data "aws_iam_policy_document" "bucket_reader" {  # build a policy document (it only produces JSON)
  statement {                                     # one statement
    sid     = "ListOnly"                          # an id for the statement (for auditing)
    effect  = "Allow"                             # allow
    actions = ["s3:ListBucket"]                   # which actions: list a bucket
    resources = [                                  # on which resources:
      "arn:aws:s3:::lab-bucket-2026"               # exactly this bucket
    ]
  }

  statement {                                     # a second statement
    sid     = "ReadObjects"                       # the id
    effect  = "Allow"                             # allow
    actions = ["s3:GetObject"]                    # which actions: read objects
    resources = [                                  # on which resources:
      "arn:aws:s3:::lab-bucket-2026/*"             # the objects IN that bucket
    ]

    condition {                                    # ...but only from this IP (least privilege in action)
      test     = "IpAddress"                       # the condition type
      variable = "aws:SourceIp"                    # check the source IP
      values   = ["203.0.113.0/24"]                # only this (documentation) range
    }
  }
}

resource "aws_iam_policy" "bucket_reader" {      # the policy resource (has an ARN, can be attached)
  name   = "lab-bucket-reader"                   # the policy's name
  policy = data.aws_iam_policy_document.bucket_reader.json   # the built JSON
}

resource "aws_iam_user" "lab" {                  # the customer user (a human/CI identity)
  name  = "lab-user"                             # the username
  tags  = { Team = "lab" }                       # a label
}

resource "aws_iam_user_policy_attachment" "lab" {   # attach the managed policy to the user
  user       = aws_iam_user.lab.name            # which user
  policy_arn = aws_iam_policy.bucket_reader.arn # which policy
}
