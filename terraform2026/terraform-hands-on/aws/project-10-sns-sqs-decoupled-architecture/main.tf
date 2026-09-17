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

# ── 1. THE BUS: one SNS topic, many consumers ─────────────────────────────────

resource "aws_sns_topic" "orders" {              # the topic: the single place events are published
  name = "${var.project}-orders"                 # unique name
}

# ── 2. THE QUEUES: one per consumer (decouples producer from consumer speed) ──

resource "aws_sqs_queue" "billing" {             # queue 1: for the billing worker
  name                      = "${var.project}-billing"     # unique name
  visibility_timeout_seconds = 60                  # hide a message for 60s while a worker processes it
  message_retention_seconds  = 86400               # keep undelivered messages 1 day
  redrive_policy = jsonencode({                    # after maxReceiveCount failures → send to the DLQ
    deadLetterTargetArn = aws_sqs_queue.billing_dlq.arn   # where poison messages go
    maxReceiveCount     = 2                         # 2 failed deliveries = poison
  })
}

resource "aws_sqs_queue" "billing_dlq" {         # the dead-letter queue: where failures pile up (so you can inspect them)
  name                      = "${var.project}-billing-dlq"  # unique name
  message_retention_seconds = 1209600              # keep failures 14 days (time to investigate)
}

resource "aws_sqs_queue" "inventory" {           # queue 2: for the inventory worker (independent of billing)
  name                      = "${var.project}-inventory"    # unique name
  visibility_timeout_seconds = 60                  # same hiding window
  message_retention_seconds  = 86400               # same retention
}

# Each queue needs a POLICY allowing ONLY our topic to publish to it (SQS is private by default)
resource "aws_sqs_queue_policy" "billing" {      # who may push to the billing queue
  queue_url = aws_sqs_queue.billing.url          # which queue
  policy = jsonencode({                           # the policy as JSON
    Version = "2012-10-17"                        # policy version
    Statement = [{                                 # one statement
      Effect    = "Allow"                          # allow
      Principal = { Service = "sns.amazonaws.com" }  # the SNS service only
      Action    = "sqs:SendMessage"                # may send messages
      Resource  = aws_sqs_queue.billing.arn        # this queue
      Condition = {                                 # ...but only from our topic:
        ArnEquals = { "aws:SourceArn" = aws_sns_topic.orders.arn }   # the topic's ARN
      }
    }]
  })
}

resource "aws_sqs_queue_policy" "inventory" {    # same for the inventory queue
  queue_url = aws_sqs_queue.inventory.url        # which queue
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.inventory.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.orders.arn } }
    }]
  })
}

# The SUBSCRIPTIONS: wire topic → each queue (this is the fan-out)
resource "aws_sns_topic_subscription" "billing" {   # topic delivers to the billing queue
  topic_arn = aws_sns_topic.orders.arn               # which topic
  protocol  = "sqs"                                  # deliver to a queue
  endpoint  = aws_sqs_queue.billing.arn              # to this queue
}

resource "aws_sns_topic_subscription" "inventory" { # topic delivers to the inventory queue
  topic_arn = aws_sns_topic.orders.arn               # which topic
  protocol  = "sqs"                                  # to a queue
  endpoint  = aws_sqs_queue.inventory.arn            # to this queue
}

# ── 3. THE WORKERS: one Lambda per queue (they never talk to each other) ──────

data "aws_iam_policy_document" "assume" {        # the assume-role policy (Lambda service may assume)
  statement {
    effect  = "Allow"                             # allow
    actions = ["sts:AssumeRole"]                  # assume this role
    principals {                                    # by whom:
      type        = "Service"                     # a service
      identifiers = ["lambda.amazonaws.com"]      # Lambda
    }
  }
}

resource "aws_iam_role" "workers" {              # the role both workers run as
  name               = "${var.project}-workers-role"   # unique name
  assume_role_policy = data.aws_iam_policy_document.assume.json   # from the document above
}

data "aws_iam_policy" "lambda_exec" {            # AWS's built-in "may write logs" policy
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"   # log permissions
}

resource "aws_iam_role_policy_attachment" "lambda_exec" {   # attach log permissions to the role
  role       = aws_iam_role.workers.id            # which role
  policy_arn = data.aws_iam_policy.lambda_exec.arn   # which policy
}

# zip up each python file (Terraform does the packaging)
data "archive_file" "billing" {                  # zip the billing consumer
  type        = "zip"                            # format
  source_file = "${path.module}/lambda/billing.py"        # the file
  output_path = "${path.module}/build/billing.zip"        # where the zip goes
}

data "archive_file" "inventory" {                # zip the inventory consumer
  type        = "zip"                            # format
  source_file = "${path.module}/lambda/inventory.py"      # the file
  output_path = "${path.module}/build/inventory.zip"      # where the zip goes
}

resource "aws_lambda_function" "billing" {       # worker 1: billing
  function_name  = "${var.project}-billing"      # unique name
  role           = aws_iam_role.workers.arn      # run as this role
  runtime        = "python3.12"                  # language + version
  handler        = "billing.handler"             # file.function inside the zip
  filename       = data.archive_file.billing.output_path   # the zipped code
  timeout        = 10                            # max seconds per invocation
  source_code_hash = data.archive_file.billing.output_base64sha256   # redeploy on code change
}

resource "aws_lambda_function" "inventory" {     # worker 2: inventory
  function_name  = "${var.project}-inventory"    # unique name
  role           = aws_iam_role.workers.arn      # same role
  runtime        = "python3.12"                  # same runtime
  handler        = "inventory.handler"           # file.function
  filename       = data.archive_file.inventory.output_path   # its zip
  timeout        = 10                            # same timeout
  source_code_hash = data.archive_file.inventory.output_base64sha256   # redeploy on change
}

# Let SQS invoke each lambda
resource "aws_lambda_permission" "billing_sqs" { # the billing queue may call the billing lambda
  statement_id  = "AllowBillingSQS"              # internal unique ID
  action        = "lambda:InvokeFunction"        # what it may do
  function_name = aws_lambda_function.billing.function_name   # which function
  principal     = "sqs.amazonaws.com"            # by the SQS service
}

resource "aws_lambda_permission" "inventory_sqs" {   # same for inventory
  statement_id  = "AllowInventorySQS"              # internal ID
  action        = "lambda:InvokeFunction"          # invoke
  function_name = aws_lambda_function.inventory.function_name   # which function
  principal     = "sqs.amazonaws.com"              # by SQS
}

# The EVENT SOURCE MAPPINGS: "poll this queue, invoke that function"
resource "aws_lambda_event_source_mapping" "billing" {   # billing queue → billing lambda
  event_source_arn = aws_sqs_queue.billing.arn  # which queue
  function_name    = aws_lambda_function.billing.function_name   # which function
  batch_size       = 10                            # up to 10 messages per invocation (this provider version: top-level arg)
}

resource "aws_lambda_event_source_mapping" "inventory" { # inventory queue → inventory lambda
  event_source_arn = aws_sqs_queue.inventory.arn  # which queue
  function_name    = aws_lambda_function.inventory.function_name   # which function
  batch_size       = 10                            # same batching
}
