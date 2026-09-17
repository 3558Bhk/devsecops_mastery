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

# ── 1. THE STREAM: the durable, ordered buffer events flow through ───────────

resource "aws_kinesis_stream" "clicks" {         # the stream
  name        = "${var.project}-clicks"          # unique name
  shard_count = 1                                # 1 shard = 1MB/s in, 2MB/s out (enough for a lab)

  # retention: Kinesis keeps data 24h by default — that's your replay window (see README "Break it")
}

# ── 2. THE CONSUMER: Lambda polled by Kinesis, in batches ────────────────────

data "aws_iam_policy_document" "assume" {        # who may assume the consumer's role
  statement {
    effect  = "Allow"                             # allow
    actions = ["sts:AssumeRole"]                  # the assume action
    principals {                                    # by whom:
      type        = "Service"                     # a service
      identifiers = ["lambda.amazonaws.com"]     # Lambda
    }
  }
}

resource "aws_iam_role" "consumer" {             # the role the consumer runs as
  name               = "${var.project}-consumer-role"   # unique name
  assume_role_policy = data.aws_iam_policy_document.assume.json   # from the document
}

data "aws_iam_policy" "lambda_exec" {            # AWS's built-in "may write logs" policy
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"   # CloudWatch Logs
}

resource "aws_iam_role_policy_attachment" "lambda_exec" {   # attach log permissions
  role       = aws_iam_role.consumer.id          # which role
  policy_arn = data.aws_iam_policy.lambda_exec.arn   # which policy
}

resource "aws_iam_role_policy" "stream_and_store" {   # the CUSTOM part: read THIS stream, write THIS bucket
  name = "clicks-consumer"                        # the policy's name
  role = aws_iam_role.consumer.id                 # which role

  policy = jsonencode({                          # the policy as JSON
    Version = "2012-10-17"                        # policy version
    Statement = [
      {                                           # statement 1: consume the stream
        Effect   = "Allow"                        # allow
        Actions  = [                               # the Kinesis operations a consumer uses
          "kinesis:DescribeStream",               # describe it
          "kinesis:DescribeStreamSummary",        # summary
          "kinesis:GetShardIterator",             # start reading
          "kinesis:GetRecords",                   # read a batch
          "kinesis:ListShards",                   # find the shards
          "kinesis:SubscribeToShard"              # (enhanced fan-out)
        ]
        Resource = [aws_kinesis_stream.clicks.arn]   # only THIS stream
      }
    ]
  })
}

data "archive_file" "aggregate" {                # zip the consumer
  type        = "zip"                            # the format
  source_file = "${path.module}/lambda/aggregate.py"      # the file
  output_path = "${path.module}/build/aggregate.zip"      # where the zip goes
}

resource "aws_s3_bucket" "stats" {               # where the per-minute stats land
  bucket = "${var.project}-click-stats-2026"     # globally unique name
}

resource "aws_s3_bucket_public_access_block" "stats" {   # lock it down
  bucket                  = aws_s3_bucket.stats.id   # which bucket
  block_public_acls       = true                     # no public ACLs
  block_public_policy     = true                     # no public bucket policies
  ignore_public_acls      = true                     # strip public ACLs
  restrict_public_buckets = true                     # public only if explicitly asked
}

resource "aws_iam_role_policy" "stats_write" {   # the consumer may write to the stats bucket
  name = "stats-bucket-write"                     # the policy's name
  role = aws_iam_role.consumer.id                 # which role

  policy = jsonencode({                          # the policy as JSON
    Version = "2012-10-17"                        # policy version
    Statement = [{                                 # one statement
      Effect   = "Allow"                          # allow
      Actions  = ["s3:PutObject"]                 # write objects
      Resource = ["${aws_s3_bucket.stats.arn}/*"] # only in THIS bucket
    }]
  })
}

resource "aws_lambda_function" "aggregate" {     # the consumer function
  function_name  = "${var.project}-aggregate"    # unique name
  role           = aws_iam_role.consumer.arn     # run as this role
  runtime        = "python3.12"                  # language + version
  handler        = "aggregate.handler"           # file.function
  filename       = data.archive_file.aggregate.output_path   # the zip
  source_code_hash = data.archive_file.aggregate.output_base64sha256   # redeploy on change
  timeout        = 30                            # a batch can take a while (Kinesis allows up to 15 min)

  environment {                                   # the bucket it writes to
    variables = {
      STATS_BUCKET = aws_s3_bucket.stats.id       # which bucket
    }
  }
}

# The EVENT SOURCE MAPPING: "keep polling this stream and invoke this function"
resource "aws_lambda_event_source_mapping" "clicks" {   # the continuous link stream → function
  event_source_arn = aws_kinesis_stream.clicks.arn   # which stream
  function_name    = aws_lambda_function.aggregate.function_name   # which function

  starting_position = "LATEST"                    # start at the tail (only NEW records; TRIM_HORIZON = replay history)
  batch_size        = 10                          # up to 10 records per invocation
}

# Kinesis must be allowed to call the Lambda (the consumer polls, but the permission is still required)
resource "aws_lambda_permission" "kinesis_invoke" {   # the Kinesis service may invoke the function
  statement_id  = "AllowKinesis"               # internal unique ID
  action        = "lambda:InvokeFunction"      # what it may do
  function_name = aws_lambda_function.aggregate.function_name   # which function
  principal     = "kinesis.amazonaws.com"      # by the Kinesis service
}

# ── 3. THE FAN-OUT: an event when a minute file lands → SNS ──────────────────

resource "aws_sns_topic" "alerts" {              # the notification bus
  name = "${var.project}-stream-alerts"          # the topic's name
}

resource "aws_sns_topic_subscription" "email" {  # deliver by email (only if you gave an address)
  count = var.alert_email == "" ? 0 : 1          # 0 or 1 subscription
  topic_arn = aws_sns_topic.alerts.arn           # which topic
  protocol  = "email"                            # deliver by email
  endpoint  = var.alert_email                    # to this address (confirm the email once!)
}

# The S3 NOTIFICATION: this is the "EventBridge" hop for S3 events —
# (for any other source you'd use aws_eventbridge_rule + a target; same idea, more sources)
resource "aws_s3_bucket_notification" "minute_files" {   # "when this bucket changes, tell X"
  bucket = aws_s3_bucket.stats.id                 # which bucket

  topic {                                          # ...tell the SNS topic
    events    = ["s3:ObjectCreated:*"]            # on ANY object creation
    topic_arn = aws_sns_topic.alerts.arn          # which topic
  }
}
