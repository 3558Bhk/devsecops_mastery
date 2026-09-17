# ============================================================================
#  Lambda — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

data "aws_iam_policy_document" "assume" {        # the trust document
  statement {
    effect  = "Allow"                             # allow
    actions = ["sts:AssumeRole"]                  # the assume action
    principals {                                    # by whom:
      type        = "Service"                     # a service
      identifiers = ["lambda.amazonaws.com"]     # Lambda
    }
  }
}

resource "aws_iam_role" "fn" {                   # the role
  name               = "lab-hello-role"          # the role's name
  assume_role_policy = data.aws_iam_policy_document.assume.json   # the trust document
}

data "aws_iam_policy" "logs" {                   # AWS's built-in "may write logs" policy
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"   # CloudWatch Logs
}

resource "aws_iam_role_policy_attachment" "logs" {   # attach it
  role       = aws_iam_role.fn.id                # which role
  policy_arn = data.aws_iam_policy.logs.arn      # which policy
}

data "archive_file" "fn" {                       # the zip (Terraform packages it)
  type        = "zip"                            # the format
  source_file = "${path.module}/hello.py"        # the single file (it goes at the zip ROOT)
  output_path = "${path.module}/build/hello.zip" # where the zip goes
}

resource "aws_lambda_function" "hello" {         # the function
  function_name  = "lab-hello"                   # the function's name
  role           = aws_iam_role.fn.arn           # the role it runs as
  runtime        = "python3.12"                  # the runtime
  handler        = "hello.handler"               # file.function inside the zip
  filename       = data.archive_file.fn.output_path   # the zip
  source_code_hash = data.archive_file.fn.output_base64sha256   # re-deploy when the code changes
  timeout        = 10                            # max seconds per invocation

  environment {                                   # environment variables
    variables = {
      STAGE = "lab"                                # example: a stage flag
    }
  }
}
