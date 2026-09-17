# ============================================================================
#  Capstone 2 — AWS Event-Driven (Serverless) Platform
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

data "aws_iam_policy_document" "assume" {        # the trust document (Lambda can assume)
  statement {
    effect  = "Allow"                             # allow
    actions = ["sts:AssumeRole"]                  # the assume action
    principals {
      type        = "Service"                     # a service
      identifiers = ["lambda.amazonaws.com"]     # Lambda
    }
  }
}

resource "aws_iam_role" "ingest" {               # the INGEST function's role
  name               = "evt-ingest-role"         # the role's name
  assume_role_policy = data.aws_iam_policy_document.assume.json   # the trust doc
}

resource "aws_iam_role" "worker" {               # the WORKER function's role
  name               = "evt-worker-role"         # the role's name
  assume_role_policy = data.aws_iam_policy_document.assume.json   # the trust doc
}

data "aws_iam_policy" "logs" {                   # the logs policy
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"   # CloudWatch Logs
}

resource "aws_iam_role_policy_attachment" "ingest_logs" {   # attach logs to ingest
  role       = aws_iam_role.ingest.id           # which role
  policy_arn = data.aws_iam_policy.logs.arn     # which policy
}

resource "aws_iam_role_policy_attachment" "worker_logs" {   # attach logs to worker
  role       = aws_iam_role.worker.id           # which role
  policy_arn = data.aws_iam_policy.logs.arn     # which policy
}

resource "aws_dynamodb_table" "orders" {         # the table
  name = "orders"                                # the table's name

  billing_mode = "PAY_PER_REQUEST"              # on-demand (no capacity to tune)

  hash_key = "order_id"                         # the partition key
  range_key = "created_at"                      # the sort key (optional, for time-range)

  attribute {                                    # the partition key attribute
    name = "order_id"                           # the attribute's name
    type = "S"                                  # a string
  }
  attribute {                                    # the sort key attribute
    name = "created_at"                         # the attribute's name
    type = "S"                                  # a string
  }
  attribute {                                    # the GSI attribute
    name = "status"                             # the attribute's name
    type = "S"                                  # a string
  }

  global_secondary_index {                       # a GSI (query by status)
    name            = "StatusIndex"              # the GSI's name
    projection_type = "ALL"                      # project all attributes
    hash_key        = "status"                   # the GSI's partition key
  }

  point_in_time_recovery { enabled = true }     # PITR (continuous backups)
  server_side_encryption { enabled = true }     # SSE (encrypted at rest)

  ttl {                                          # TTL (auto-expire old rows)
    attribute_name = "ttl"                       # the TTL attribute
  }
}

resource "aws_iam_role_policy" "ingest_dynamo" {  # the ingest's DynamoDB permission
  name   = "dynamo-write"                        # the policy's name
  role   = aws_iam_role.ingest.id                # which role

  policy = jsonencode({                           # the policy
    Version = "2012-10-17"                         # the version
    Statement = [{
      Effect   = "Allow"                           # allow
      Action   = ["dynamodb:PutItem", "dynamodb:Query"]   # write + read
      Resource = [aws_dynamodb_table.orders.arn, "${aws_dynamodb_table.orders.arn}/index/*"]   # the table + its GSI
    }]
  })
}

data "archive_file" "ingest" {                   # zip the ingest code
  type        = "zip"                            # the format
  source_file = "${path.module}/ingest.py"       # the file
  output_path = "${path.module}/build/ingest.zip"   # where the zip goes
}

resource "aws_lambda_function" "ingest" {        # the ingest function
  function_name  = "evt-ingest"                  # the name
  role           = aws_iam_role.ingest.arn       # the role
  runtime        = "python3.12"                  # the runtime
  handler        = "ingest.handler"              # file.function
  filename       = data.archive_file.ingest.output_path   # the zip
  source_code_hash = data.archive_file.ingest.output_base64sha256   # redeploy on change
  timeout        = 30                            # max seconds
}

resource "aws_s3_bucket" "uploads" {             # the uploads bucket
  bucket = "evt-uploads-${random_string.suffix.result}"   # a unique name
}

resource "random_string" "suffix" {              # a random suffix
  length  = 6                                    # 6 chars
  special = false                                # no special chars
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sse" {   # encrypt objects
  bucket = aws_s3_bucket.uploads.id              # which bucket

  rule {                                          # the rule
    apply_server_side_encryption_by_default {     # SSE by default
      sse_algorithm = "AES256"                   # AWS-managed key
    }
  }
}

resource "aws_lambda_permission" "allow_s3" {    # allow S3 to invoke the Lambda
  statement_id  = "AllowS3"                      # the statement's id
  action        = "lambda:InvokeFunction"        # the action
  function_name = aws_lambda_function.ingest.arn   # which function
  principal     = "s3.amazonaws.com"             # by S3
  source_arn    = aws_s3_bucket.uploads.arn      # only from this bucket
}

resource "aws_s3_bucket_notification" "uploads" {   # the S3 → Lambda trigger
  bucket = aws_s3_bucket.uploads.id              # which bucket

  lambda_function {                               # the target
    lambda_function_arn = aws_lambda_function.ingest.arn   # the function
    events              = ["s3:ObjectCreated:*"] # on any new object
    filter_prefix       = "uploads/"             # only the uploads/ prefix
  }
}

resource "aws_sns_topic" "events" {              # the topic (the fan-out point)
  name = "evt-events"                            # the topic's name
}

resource "aws_sqs_queue" "worker" {              # the worker queue (the buffer)
  name                      = "evt-worker-queue" # the queue's name
  visibility_timeout_seconds = 60                 # the lock time (a worker has 60s)
  message_retention_seconds  = 86400              # keep 1 day
}

resource "aws_sqs_queue" "dlq" {                 # the dead-letter queue
  name                      = "evt-worker-dlq"   # the queue's name
  message_retention_seconds = 1209600            # keep 14 days (the max)
}

resource "aws_sqs_queue_redrive_policy" "worker" {   # wire the DLQ to the worker
  queue_url = aws_sqs_queue.worker.url

  redrive_policy = jsonencode({
    dead_letter_target_arn = aws_sqs_queue.dlq.arn
    max_receive_count      = 3
  })
}

resource "aws_sns_topic_subscription" "sqs" {    # the topic → the queue
  topic_arn = aws_sns_topic.events.arn           # which topic
  protocol  = "sqs"                              # deliver to SQS
  endpoint  = aws_sqs_queue.worker.arn           # to which queue
}

resource "aws_sqs_queue_policy" "allow_sns" {    # allow the topic to publish to the queue
  queue_url = aws_sqs_queue.worker.url           # which queue

  policy = jsonencode({                           # the policy
    Version = "2012-10-17"                         # the version
    Statement = [{
      Effect    = "Allow"                          # allow
      Principal = { Service = "sns.amazonaws.com" }  # by SNS
      Action    = "sqs:SendMessage"                # send a message
      Resource  = aws_sqs_queue.worker.arn         # to this queue
      Condition = { ArnEquals = { "aws:SourceArn" = aws_sns_topic.events.arn } }   # only from this topic
    }]
  })
}

resource "aws_lambda_event_source_mapping" "worker" {   # the SQS → Lambda wiring
  function_name = aws_lambda_function.worker.arn   # which function
  event_source_arn = aws_sqs_queue.worker.arn     # which queue
  batch_size     = 1                             # one message at a time
  enabled        = true                          # on
}

resource "aws_iam_role_policy" "worker_perms" {  # the worker's permissions
  name   = "worker-perms"                        # the policy's name
  role   = aws_iam_role.worker.id                # which role

  policy = jsonencode({                           # the policy
    Version = "2012-10-17"                         # the version
    Statement = [{
      Effect   = "Allow"                           # allow
      Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]   # read/delete from the queue
      Resource = [aws_sqs_queue.worker.arn]        # this queue
    }, {
      Effect   = "Allow"                           # allow
      Action   = ["dynamodb:GetItem", "dynamodb:Query"]   # read the table
      Resource = [aws_dynamodb_table.orders.arn]   # the table
    }, {
      Effect   = "Allow"                           # allow
      Action   = ["sns:Publish"]                   # publish to the topic
      Resource = [aws_sns_topic.events.arn]        # this topic
    }]
  })
}

data "archive_file" "worker" {                   # zip the worker code
  type        = "zip"                            # the format
  source_file = "${path.module}/worker.py"       # the file
  output_path = "${path.module}/build/worker.zip"   # where the zip goes
}

resource "aws_lambda_function" "worker" {        # the worker function
  function_name  = "evt-worker"                  # the name
  role           = aws_iam_role.worker.arn       # the role
  runtime        = "python3.12"                  # the runtime
  handler        = "worker.handler"              # file.function
  filename       = data.archive_file.worker.output_path   # the zip
  source_code_hash = data.archive_file.worker.output_base64sha256   # redeploy on change
  timeout        = 30                            # max seconds
}

resource "aws_api_gateway_rest_api" "query" {    # the API
  name = "evt-query"                             # the API's name
  endpoint_configuration { types = ["EDGE"] }    # public
}

resource "aws_api_gateway_resource" "orders" {   # the path: /orders
  rest_api_id = aws_api_gateway_rest_api.query.id   # which API
  parent_id   = aws_api_gateway_rest_api.query.root_resource_id   # under /
  path_part   = "orders"                             # the path
}

resource "aws_api_gateway_method" "orders_get" {   # the verb: GET /orders
  rest_api_id = aws_api_gateway_rest_api.query.id   # which API
  resource_id = aws_api_gateway_resource.orders.id  # which path
  http_method = "GET"                            # the verb
  authorization = "NONE"                         # open (add Cognito/IAM for real)
}

resource "aws_api_gateway_integration" "orders_get" {   # the integration
  rest_api_id = aws_api_gateway_rest_api.query.id   # which API
  resource_id = aws_api_gateway_resource.orders.id  # which path
  http_method = "GET"                            # the verb
  type        = "AWS_PROXY"                      # proxy
  uri         = aws_lambda_function.query.arn    # the query Lambda
}

resource "aws_api_gateway_deployment" "query" {  # the deployment
  rest_api_id = aws_api_gateway_rest_api.query.id   # which API
  stage_name  = "prod"                           # the stage
  triggers = { query = aws_lambda_function.query.arn }   # re-deploy on change
}

data "archive_file" "query" {                   # zip the query code
  type        = "zip"                            # the format
  source_file = "${path.module}/query.py"        # the file
  output_path = "${path.module}/build/query.zip"   # where the zip goes
}

resource "aws_lambda_function" "query" {        # the query function
  function_name  = "evt-query"                  # the name
  role           = aws_iam_role.ingest.arn      # reuse the ingest role (it has Query)
  runtime        = "python3.12"                  # the runtime
  handler        = "query.handler"               # file.function
  filename       = data.archive_file.query.output_path   # the zip
  source_code_hash = data.archive_file.query.output_base64sha256   # redeploy on change
  timeout        = 10                            # max seconds
}
