# ============================================================================
#  Secrets Manager — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_secretsmanager_secret" "db" {       # the secret (metadata)
  name       = "lab/db-credentials"              # the secret's name
  description = "lab database credentials"       # a description
  tags       = { env = "lab" }                   # a label
}

resource "aws_secretsmanager_secret_version" "db" {   # the secret (value)
  secret_id = aws_secretsmanager_secret.db.id     # which secret
  secret_string = jsonencode({                     # the value (JSON)
    username = "app"                              # the user
    password = "Lab-Password-123"                 # the password (CHANGE)
    host     = "db.lab.internal"                  # the host
  })
}

resource "aws_secretsmanager_secret_rotation" "db" {   # the rotation config
  secret_id = aws_secretsmanager_secret.db.id     # which secret
  rotation_lambda_arn = aws_lambda_function.rotator.arn   # the rotation Lambda
  rotation_rules {                                 # the rules
    schedule_expression = "rate(30 days)"         # rotate every 30 days
  }
}

data "aws_iam_policy_document" "rotator_assume" {   # who may assume the rotator
  statement {
    effect  = "Allow"                             # allow
    actions = ["sts:AssumeRole"]                  # the assume action
    principals {
      type        = "Service"                     # a service
      identifiers = ["lambda.amazonaws.com"]     # Lambda
    }
  }
}

resource "aws_iam_role" "rotator" {               # the rotator role
  name               = "lab-rotator-role"        # the role's name
  assume_role_policy = data.aws_iam_policy_document.rotator_assume.json   # the trust document
}

data "aws_iam_policy" "lambda_logs" {             # the logs policy
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"   # CloudWatch Logs
}

resource "aws_iam_role_policy_attachment" "rotator_logs" {   # attach logs
  role       = aws_iam_role.rotator.id           # which role
  policy_arn = data.aws_iam_policy.lambda_logs.arn   # which policy
}

resource "aws_iam_role_policy" "rotator_perms" {  # the rotation Lambda's permissions
  name   = "rotator-perms"                        # the policy's name
  role   = aws_iam_role.rotator.id                # which role

  policy = jsonencode({                           # the policy
    Version = "2012-10-17"                         # the version
    Statement = [{                                 # one statement
      Effect   = "Allow"                           # allow
      Action   = ["secretsmanager:DescribeSecret", "secretsmanager:RotateSecret", "secretsmanager:PutSecretValue"]   # rotation actions
      Resource = [aws_secretsmanager_secret.db.arn]   # this secret only
    }, {
      Effect   = "Allow"                           # allow
      Action   = ["lambda:InvokeFunction"]         # invoke the rotator
      Resource = [aws_lambda_function.rotator.arn] # this function
    }]
  })
}

resource "aws_lambda_function" "rotator" {        # the rotation function
  function_name = "lab-rotator"                   # the name
  role          = aws_iam_role.rotator.arn        # the role
  runtime       = "python3.12"                    # the runtime
  handler       = "index.handler"                 # file.function
  filename      = "${path.module}/build/rotator.zip"   # the code
  timeout       = 300                             # rotation can take a while
  environment {
    variables = {
      SECRET_ID = aws_secretsmanager_secret.db.id   # which secret to rotate
    }
  }
}

resource "aws_iam_role" "reader" {                # the app's role
  name = "lab-app-reader"                         # the role's name

  assume_role_policy = jsonencode({               # the trust document
    Version = "2012-10-17"                         # the version
    Statement = [{
      Effect    = "Allow"                          # allow
      Action    = "sts:AssumeRole"                 # the assume action
      Principal = { Service = "ec2.amazonaws.com" }   # assumed by EC2
    }]
  })
}

resource "aws_iam_role_policy" "reader_perms" {   # the read permission
  name = "read-db-secret"                          # the policy's name
  role = aws_iam_role.reader.id                    # which role

  policy = jsonencode({                            # the policy
    Version = "2012-10-17"                          # the version
    Statement = [{
      Effect   = "Allow"                            # allow
      Action   = ["secretsmanager:GetSecretValue"]  # read the secret
      Resource = [aws_secretsmanager_secret.db.arn] # THIS secret only (never *)
    }]
  })
}
