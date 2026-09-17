# ============================================================================
#  Inline Policies — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

data "aws_iam_policy_document" "assume" {        # the assume-role policy document
  statement {
    effect  = "Allow"                             # allow
    actions = ["sts:AssumeRole"]                  # the "become the role" action
    principals {                                    # by whom:
      type        = "Service"                     # a service (not a human)
      identifiers = ["lambda.amazonaws.com"]     # Lambda may assume it
    }
  }
}

resource "aws_iam_role" "lab" {                  # the role
  name               = "lab-inline-role"         # the role's name
  assume_role_policy = data.aws_iam_policy_document.assume.json   # the trust document
}

resource "aws_iam_role_policy" "writer" {        # the inline policy resource
  name = "bucket-writer"                         # the policy name (unique on the role)
  role = aws_iam_role.lab.id                     # which role it lives on

  # here the JSON is inline (no separate aws_iam_policy object needed)
  policy = jsonencode({                          # build the JSON directly
    Version = "2012-10-17"                        # the policy version
    Statement = [{                                 # one statement
      Effect = "Allow"                             # allow
      Actions = [                                   # the exact actions:
        "s3:PutObject",                            # write an object
        "s3:GetObject"                             # read an object
      ]
      Resource = [                                  # on the exact resources:
        "arn:aws:s3:::lab-bucket-2026/uploads/*"    # the uploads prefix only
      ]
    }]
  })
}
