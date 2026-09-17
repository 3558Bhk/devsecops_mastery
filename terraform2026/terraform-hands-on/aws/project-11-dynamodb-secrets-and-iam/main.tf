terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }   # AWS provider, any 5.x
  }
}

provider "aws" {                                 # configure the AWS provider
  region = var.region                            # from the variable
}

data "aws_caller_identity" "current" {           # data block: our own account ID (for building ARNs)
  # no arguments — it returns the account the provider is logged in as
}

# ── 1. THE TABLE: DynamoDB ────────────────────────────────────────────────────

resource "aws_dynamodb_table" "orders" {         # the table
  name         = "${var.project}-orders"         # unique table name
  billing_mode = "PAY_PER_REQUEST"               # pay per use (no capacity planning; free-tier friendly)

  hash_key  = "order_id"                          # partition key: how items are split across storage
  range_key = null                                # no sort key (single-attribute items)

  attribute {                                     # declare the partition key's type
    name = "order_id"                             # same as hash_key
    type = "S"                                    # S = string
  }

  attribute {                                     # declare the GSI's key attribute
    name = "status"                               # the attribute we index
    type = "S"                                    # string
  }

  global_secondary_index {                        # a GSI: a SECOND view of the table, keyed differently
    name            = "StatusIndex"               # the index name
    projection_type = "ALL"                       # include every attribute in index results
    hash_key        = "status"                    # the GSI's partition key
  }

  ttl {                                            # TTL: auto-delete old items (free)
    attribute_name = "expires_at"                 # items with this attribute's unix time passed get deleted
    enabled        = true                         # turn it on
  }

  point_in_time_recovery { enabled = true }       # PITR: restore the table to any second in the last 35 days
  stream_enabled       = false                    # no change stream needed for this lab
  server_side_encryption { enabled = true }       # encrypt at rest (KMS default key)
}

# ── 2. THE SECRETS: SSM Parameter Store + Secrets Manager ─────────────────────

resource "aws_ssm_parameter" "env" {             # a plain (non-secret) config parameter
  name  = "/${var.project}/app/env"              # the parameter path (namespaced by project)
  type  = "String"                               # a plain string
  value = "dev"                                  # the value
}

resource "aws_ssm_parameter" "api_token" {       # a SecureString: stored ENCRYPTED, needs decryption to read
  name  = "/${var.project}/app/api_token"        # the parameter path
  type  = "SecureString"                         # encrypted at rest with KMS
  value = var.api_token                          # the value from the sensitive variable
}

resource "aws_secretsmanager_secret" "db_password" {   # the secret (for things that ROTATE)
  name = "${var.project}/app/db-password"        # the secret's name (namespaced)
  description = "DB password for the orders app"  # human label

  tags = { project = var.project }               # label
}

resource "aws_secretsmanager_secret_version" "db_password" {   # the secret's VALUE (versioned)
  secret_id = aws_secretsmanager_secret.db_password.id   # which secret
  secret_string = var.db_password                # the value (changing it = a NEW version, old ones recoverable)
}

# ── 3. THE IDENTITY: a role scoped to EXACTLY the resources above ────────────

data "aws_iam_policy_document" "assume" {        # who may assume the role
  statement {
    effect  = "Allow"                             # allow
    actions = ["sts:AssumeRole"]                  # the assume action
    principals {                                    # by whom:
      type        = "Service"                     # a service (e.g. your app's EC2/Lambda)
      identifiers = ["ec2.amazonaws.com", "lambda.amazonaws.com"]   # EC2 or Lambda can run as it
    }
  }
}

resource "aws_iam_role" "app" {                  # the app's role
  name               = "${var.project}-app-role" # unique name
  assume_role_policy = data.aws_iam_policy_document.assume.json   # from the document
}

data "aws_iam_policy_document" "app_permissions" {   # the CUSTOM policy: exactly what the app needs
  statement {                                       # statement 1: read/write THIS table only
    effect  = "Allow"                               # allow
    actions = [                                     # the DynamoDB actions an app uses
      "dynamodb:GetItem",                           # read one item
      "dynamodb:PutItem",                           # write one item
      "dynamodb:Query",                             # query the table (and GSIs)
      "dynamodb:Scan"                               # full scan (avoid in prod)
    ]
    resources = [aws_dynamodb_table.orders.arn]    # ONLY this table (least privilege!)
  }

  statement {                                       # statement 2: read the config + token parameters
    effect  = "Allow"                               # allow
    actions = ["ssm:GetParameter"]                  # read a parameter
    resources = [                                     # only THESE two parameters:
      aws_ssm_parameter.env.arn,                      # the env parameter
      aws_ssm_parameter.api_token.arn                 # the token (SecureString)
    ]
  }

  statement {                                       # statement 3: read the DB password secret
    effect  = "Allow"                               # allow
    actions = ["secretsmanager:GetSecretValue"]     # read the secret value
    resources = [aws_secretsmanager_secret.db_password.arn]   # only this secret
  }
}

# A policy DOCUMENT only produces JSON — to attach it we must wrap it in a real policy resource
resource "aws_iam_policy" "app" {                    # the policy object (carries the document above)
  name   = "${var.project}-app-policy"              # unique policy name
  policy = data.aws_iam_policy_document.app_permissions.json   # the built JSON
}

resource "aws_iam_role_policy_attachment" "app" {   # attach the custom policy to the role
  role       = aws_iam_role.app.id                # which role
  policy_arn = aws_iam_policy.app.arn             # the policy resource we just made
}
