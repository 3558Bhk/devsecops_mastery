terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    aws     = { source = "hashicorp/aws",     version = "~> 5.0" }   # AWS provider, any 5.x
    archive = { source = "hashicorp/archive", version = "~> 2.0" }   # helper provider that zips files
  }
}

provider "aws" {                                 # configure the AWS provider
  region = "us-east-1"                           # where everything is created
}

# ── 1. THE BUCKET: the trigger source ──────────────────────────────────────────

resource "aws_s3_bucket" "events" {              # the bucket whose uploads trigger the function
  bucket = "my-lambda-lab-events-2026"           # globally unique name
  tags   = { Project = var.project }             # label
}

# ── 2. THE IAM ROLE: the identity Lambda runs as ───────────────────────────────

data "aws_iam_policy_document" "assume" {        # data block: build a JSON policy document
  statement {                                     # one statement in the document
    effect  = "Allow"                             # allow (the only other value is Deny)
    actions = ["sts:AssumeRole"]                  # the action granted: "become this role"

    principals {                                   # WHO may assume the role
      type        = "Service"                     # an AWS service (not a human)
      identifiers = ["lambda.amazonaws.com"]      # specifically the Lambda service
    }
  }
}

resource "aws_iam_role" "lambda" {               # the role itself
  name               = "${var.project}-lambda-role"   # unique role name
  assume_role_policy = data.aws_iam_policy_document.assume.json   # the "who may assume me" policy
}

data "aws_iam_policy" "lambda_exec" {            # data block: LOOK UP AWS's built-in policy (don't write it)
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"   # grants log-writing permissions
}

resource "aws_iam_role_policy_attachment" "lambda_exec" {   # glue the policy to the role
  role       = aws_iam_role.lambda.id            # which role
  policy_arn = data.aws_iam_policy.lambda_exec.arn   # which policy
}

# ── 3. THE FUNCTION: the code that runs ───────────────────────────────────────

data "archive_file" "package" {                  # zip up the python file so Lambda can receive it
  type        = "zip"                            # archive format
  source_file = "${path.module}/lambda/lambda_function.py"   # the file to zip (path.module = this folder)
  output_path = "${path.module}/build/function.zip"          # where to write the zip
}

resource "aws_lambda_function" "hello" {         # the Lambda function
  function_name  = "${var.project}-hello"        # unique function name
  role           = aws_iam_role.lambda.arn       # run AS this role (its permissions become the function's)
  runtime        = "python3.12"                  # the code's language + version
  handler        = "lambda_function.handler"     # file.function inside the zip
  filename       = data.archive_file.package.output_path   # the zipped code from above
  timeout        = 30                            # max seconds per invocation
  source_code_hash = data.archive_file.package.output_base64sha256   # redeploys automatically when the code changes
}

# ── 4. THE TRIGGER: "when X happens in the bucket, call the function" ─────────

resource "aws_lambda_permission" "allow_s3" {    # tell Lambda: the S3 service is allowed to invoke me
  statement_id  = "AllowS3"                      # an internal unique ID for this permission
  action        = "lambda:InvokeFunction"        # what S3 may do
  function_name = aws_lambda_function.hello.function_name   # which function
  principal     = "s3.amazonaws.com"             # who is allowed: the S3 service
}

resource "aws_s3_bucket_notification" "trigger" {   # tell the bucket: on new objects, call the function
  bucket = aws_s3_bucket.events.id               # which bucket

  lambda_function {                                # the "call a lambda" part of the notification
    lambda_function_arn = aws_lambda_function.hello.arn   # which function to call
    events              = ["s3:ObjectCreated:*"]          # fire on every create (upload, copy, multipart complete)
  }
}
