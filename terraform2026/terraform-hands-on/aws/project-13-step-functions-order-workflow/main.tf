terraform {                                      # the terraform block: settings about Terraform itself
  required_version = ">= 1.5"                    # minimum Terraform version
  required_providers {
    aws     = { source = "hashicorp/aws",     version = "~> 5.0" }   # AWS provider
    archive = { source = "hashicorp/archive", version = "~> 2.0" }   # zips the lambda code
  }
}

provider "aws" {                                 # configure the AWS provider
  region = var.region                            # from the variable
}

# ── 1. THE ENDPOINTS the pipeline uses ───────────────────────────────────────

resource "aws_s3_bucket" "archive" {             # where finished orders are persisted
  bucket = "${var.project}-order-archive-2026"   # globally unique name
}

resource "aws_s3_bucket_public_access_block" "archive" {   # lock it down (S3 defaults are public-ish)
  bucket                  = aws_s3_bucket.archive.id   # which bucket
  block_public_acls       = true                     # no public ACLs
  block_public_policy     = true                     # no public bucket policies
  ignore_public_acls      = true                     # strip public ACLs
  restrict_public_buckets = true                     # public only if explicitly asked
}

resource "aws_sns_topic" "large_orders" {        # where "human, big order!" alerts go
  name = "${var.project}-large-orders"           # the topic's name
}

# ── 2. THE WORKERS: three small Lambdas (none of them calls another) ─────────

data "aws_iam_policy_document" "assume" {        # who may assume the workers' role
  statement {
    effect  = "Allow"                             # allow
    actions = ["sts:AssumeRole"]                  # the assume action
    principals {                                    # by whom:
      type        = "Service"                     # a service
      identifiers = ["lambda.amazonaws.com"]     # Lambda
    }
  }
}

resource "aws_iam_role" "workers" {              # the role all three workers run as
  name               = "${var.project}-workers-role"   # unique name
  assume_role_policy = data.aws_iam_policy_document.assume.json   # from the document
}

data "aws_iam_policy" "lambda_exec" {            # AWS's built-in "may write logs" policy
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"   # CloudWatch Logs
}

resource "aws_iam_role_policy_attachment" "lambda_exec" {   # attach log permissions
  role       = aws_iam_role.workers.id           # which role
  policy_arn = data.aws_iam_policy.lambda_exec.arn   # which policy
}

resource "aws_iam_role_policy" "endpoint_access" {   # the CUSTOM part: S3 + SNS, only these ARNs
  name = "pipeline-endpoints"                     # the policy's name
  role = aws_iam_role.workers.id                  # which role

  policy = jsonencode({                          # the policy as JSON
    Version = "2012-10-17"                        # policy version
    Statement = [
      {                                           # statement 1: write to the archive bucket
        Effect   = "Allow"                        # allow
        Actions  = ["s3:PutObject"]               # write objects
        Resource = ["${aws_s3_bucket.archive.arn}/*"]   # only objects in THIS bucket
      },
      {                                           # statement 2: publish alerts to the topic
        Effect   = "Allow"                        # allow
        Actions  = ["sns:Publish"]                # publish messages
        Resource = [aws_sns_topic.large_orders.arn]    # only THIS topic
      }
    ]
  })
}

data "archive_file" "received" {                 # zip worker 1
  type        = "zip"                            # the format
  source_file = "${path.module}/lambda/order_received.py"     # the file
  output_path = "${path.module}/build/received.zip"           # where the zip goes
}

data "archive_file" "notify" {                   # zip worker 2
  type        = "zip"                            # the format
  source_file = "${path.module}/lambda/notify_large.py"       # the file
  output_path = "${path.module}/build/notify.zip"             # where the zip goes
}

data "archive_file" "archive" {                  # zip worker 3
  type        = "zip"                            # the format
  source_file = "${path.module}/lambda/archive_order.py"      # the file
  output_path = "${path.module}/build/archive.zip"            # where the zip goes
}

resource "aws_lambda_function" "received" {      # worker 1: validate
  function_name  = "${var.project}-order-received"   # unique name
  role           = aws_iam_role.workers.arn      # run as this role
  runtime        = "python3.12"                  # language + version
  handler        = "order_received.handler"      # file.function
  filename       = data.archive_file.received.output_path   # the zip
  source_code_hash = data.archive_file.received.output_base64sha256   # redeploy on change
  timeout        = 10                            # max seconds
}

resource "aws_lambda_function" "notify" {        # worker 2: page via SNS
  function_name  = "${var.project}-notify-large"   # unique name
  role           = aws_iam_role.workers.arn      # same role
  runtime        = "python3.12"                  # same runtime
  handler        = "notify_large.handler"        # its file.function
  filename       = data.archive_file.notify.output_path   # its zip
  source_code_hash = data.archive_file.notify.output_base64sha256   # redeploy on change
  timeout        = 10                            # same timeout

  environment {                                   # the topic it publishes to
    variables = {
      TOPIC_ARN = aws_sns_topic.large_orders.arn  # which topic
    }
  }
}

resource "aws_lambda_function" "archive" {       # worker 3: persist to S3
  function_name  = "${var.project}-archive-order"   # unique name
  role           = aws_iam_role.workers.arn      # same role
  runtime        = "python3.12"                  # same runtime
  handler        = "archive_order.handler"       # its file.function
  filename       = data.archive_file.archive.output_path   # its zip
  source_code_hash = data.archive_file.archive.output_base64sha256   # redeploy on change
  timeout        = 10                            # same timeout

  environment {                                   # the bucket it writes to
    variables = {
      ARCHIVE_BUCKET = aws_s3_bucket.archive.id   # which bucket
    }
  }
}

# ── 3. THE ORCHESTRATOR: a Step Functions state machine ──────────────────────

data "aws_iam_policy_document" "states_assume" {  # who may assume the machine's role
  statement {
    effect  = "Allow"                             # allow
    actions = ["sts:AssumeRole"]                  # the assume action
    principals {                                    # by whom:
      type        = "Service"                     # a service
      identifiers = ["states.amazonaws.com"]     # Step Functions
    }
  }
}

resource "aws_iam_role" "sfn" {                  # the role the machine uses to call the Lambdas
  name               = "${var.project}-sfn-role" # unique name
  assume_role_policy = data.aws_iam_policy_document.states_assume.json   # from the document
}

resource "aws_iam_role_policy" "sfn_invoke" {    # the machine may invoke EXACTLY these three Lambdas
  name = "invoke-workers"                        # the policy's name
  role = aws_iam_role.sfn.id                     # which role

  policy = jsonencode({                          # the policy as JSON
    Version = "2012-10-17"                        # policy version
    Statement = [{                                 # one statement
      Effect   = "Allow"                          # allow
      Actions  = ["lambda:InvokeFunction"]        # invoke a function
      Resource = [                                  # only these functions:
        aws_lambda_function.received.arn,           # worker 1
        aws_lambda_function.notify.arn,             # worker 2
        aws_lambda_function.archive.arn             # worker 3
      ]
    }]
  })
}

resource "aws_sfn_state_machine" "order_pipeline" {   # the machine itself
  name       = "${var.project}-order-pipeline"   # unique name
  role_arn   = aws_iam_role.sfn.arn              # the role that may call the workers
  type       = "STANDARD"                        # STANDARD = at-least-once, 1 year history (use EXPRESS for millions of tiny events)

  # The ASL definition: the whole flow as data. Change it, `apply`, new flow.
  definition = jsonencode({                       # build the JSON from Terraform (so ARNs interpolate)
    Comment   = "Real-time order pipeline: validate -> route by amount -> archive"   # shown in the console
    StartAt   = "ReceiveOrder"                    # the first state

    States = {                                     # every state, by name
      ReceiveOrder = {                              # step 1: validate
        Type    = "Task"                           # a Lambda task
        Resource = aws_lambda_function.received.arn  # which Lambda
        Next    = "RouteByAmount"                  # then go to the Choice
      }

      RouteByAmount = {                             # the branch
        Type = "Choice"                             # a decision state
        Choices = [                                  # evaluated top to bottom:
          {                                          # choice 1: big order?
            Variable           = "$.amount"         # the field in the order JSON
            NumericGreaterThan = var.big_order_threshold   # above the threshold?
            Next               = "NotifyLargeOrder"        # yes -> flag it
          }
        ]
        Default = "ArchiveOrder"                     # no match (small order) -> straight to archive
      }

      NotifyLargeOrder = {                          # step 2 (large branch): page a human
        Type    = "Task"                            # a Lambda task
        Resource = aws_lambda_function.notify.arn   # the notifier
        Next    = "ArchiveOrder"                    # then also archive
      }

      ArchiveOrder = {                              # final step: persist
        Type    = "Task"                            # a Lambda task
        Resource = aws_lambda_function.archive.arn  # the archiver
        End     = true                              # the run finishes here

        Retry = [                                    # if it fails, try again (transient errors only):
          {
            ErrorNames      = ["States.TaskFailed"]  # which errors to retry
            IntervalSeconds = 1                       # first retry after 1s
            MaxAttempts     = 3                       # up to 3 tries
            BackoffRate     = 2                       # 1s, then 2s (exponential)
          }
        ]
      }
    }
  })
}
