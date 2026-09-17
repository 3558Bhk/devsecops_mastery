# AWS 8 — Serverless (Lambda, API Gateway, Messaging)

> **⏱️ Time to complete: ~75 min** (read + deploy a Lambda with an S3 trigger)

## 8.1 Lambda Function (the pattern)

```hcl
# Execution role (what the function can call)
data "aws_iam_policy_document" "lambda_assume" {   # the Lambda trust doc
  statement {                                    # one statement
    effect  = "Allow"                            # allow
    actions = ["sts:AssumeRole"]                 # assume-role
    principals { type = "Service"; identifiers = ["lambda.amazonaws.com"] }  # trusted by Lambda
  }
}

resource "aws_iam_role" "lambda" {           # the execution role
  name               = "${local.name_prefix}-lambda"   # role name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json   # the trust policy
}

resource "aws_iam_role_policy" "lambda" {     # an inline policy on the role
  role = aws_iam_role.lambda.id               # the role
  policy = jsonencode({                        # the policy document
    Version = "2012-10-17"                      # IAM policy version
    Statement = [{                              # one statement
      Effect = "Allow"                          # allow
      Action = [                                 # the actions
        "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents",   # CloudWatch Logs
        "s3:GetObject",                          # read S3
        "dynamodb:PutItem", "dynamodb:GetItem",  # DynamoDB
      ]
      Resource = ["*"]   # tighten in prod
    }]
  })
}

# The function (code from a zip in the repo, or S3)
resource "aws_lambda_function" "handler" {   # the Lambda function
  function_name = "${local.name_prefix}-handler"   # the function name
  role          = aws_iam_role.lambda.arn     # the execution role
  runtime       = "python3.12"                # the runtime
  handler       = "app.handler"          # file.function
  filename      = "${path.module}/lambda.zip"   # the local zip
  source_code_hash = filebase64sha256("${path.module}/lambda.zip")   # hash (detects changes)

  memory_size   = 256                       # 256 MB
  timeout       = 30                        # 30 s
  architectures = ["x86_64"]            # or ["arm64"] (cheaper)

  environment {                              # environment
    variables = {                            # environment variables
      ENVIRONMENT   = var.environment        # the env
      TABLE_NAME    = aws_dynamodb_table.orders.name   # the DynamoDB table
    }
  }

  # (optional) put in a VPC (to reach private resources)
  # vpc_config {
  #   subnet_ids         = aws_subnet.private[*].id
  #   security_group_ids = [aws_security_group.lambda.id]
  # }

  tags = { Name = "${local.name_prefix}-handler" }
}
```

> **Deployment tip:** for anything beyond toy code, zip the code (or keep a **layer**) and use `source_code_hash` so Terraform knows when to update. For real projects, package with **SAM/CDK** or push to **S3** and reference by `s3_bucket`/`s3_key`.

### Lambda permissions (who may invoke)

```hcl
# S3 can invoke on PUT
resource "aws_lambda_permission" "s3" {       # a lambda invoke permission
  statement_id  = "AllowS3"                    # the statement id
  action        = "lambda:InvokeFunction"      # the invoke action
  function_name = aws_lambda_function.handler.function_name   # the function
  principal     = "s3.amazonaws.com"           # S3 may invoke
  source_arn    = aws_s3_bucket.app.arn        # only from this bucket
  source_account = data.aws_caller_identity.current.account   # only from this account
}

# S3 event → Lambda (the common trigger)
resource "aws_s3_bucket_notification" "app" {  # an S3 bucket notification
  bucket = aws_s3_bucket.app.id               # the bucket
  lambda_function_arn = aws_lambda_function.handler.arn   # the function to notify
  events              = ["s3:ObjectCreated:*"]   # on object created
  filter_prefix       = "uploads/"             # only under uploads/
}
```

### VPC + Lambda

When Lambda must reach **private** resources (RDS, EFS, private API), put it in a **VPC** (private subnets + ENI). Trade-off: cold starts increase (ENI attach), and you need a **NAT** for outbound internet.

## 8.2 API Gateway (HTTP front door)

```hcl
# HTTP API (simpler, cheaper) — REST API for full control
resource "aws_api_gateway_http_api" "api" {   # an HTTP API
  name = "${local.name_prefix}-api"           # the API name
}

resource "aws_api_gateway_http_api_stage" "stage" {   # a stage (e.g. prod)
  api_id      = aws_api_gateway_http_api.api.id   # the API
  stage_name  = var.environment                   # the stage name
  auto_deploy = true                              # auto-deploy on changes
}

# Route → Lambda (integration)
resource "aws_api_gateway_route" "create" {   # a route
  api_id = aws_api_gateway_http_api.api.id   # the API
  route_key = "GET /items/{id}"              # the route key
  target = "integrations/aws:${aws_lambda_function.handler.arn}"   # integrate with the Lambda
}

# Lambda invoke permission for API GW
resource "aws_lambda_permission" "apigw" {     # a lambda invoke permission
  statement_id  = "AllowAPIGW"                 # the statement id
  action        = "lambda:InvokeFunction"      # the invoke action
  function_name = aws_lambda_function.handler.function_name   # the function
  principal     = "apigateway.amazonaws.com"   # API Gateway may invoke
}
```

- **HTTP API** = cheap, simple, Lambda/HTTP integrations.
- **REST API** = full (authorization types, request/response models, caching, WebSocket).
- **Lambda authorizer** or **Cognito** for auth.

## 8.3 Messaging (SQS / SNS / EventBridge)

### SQS (queue — decouple + buffer)

```hcl
resource "aws_sqs_queue" "orders" {           # an SQS queue
  name                      = "${local.name_prefix}-orders"   # the name
  visibility_timeout_seconds = 60              # in-flight visibility (s)
  message_retention_seconds  = 345600        # 4 days
  receive_wait_time_seconds  = 10             # long polling (fewer empty reads)
  # FIFO: name must end .fifo
  # fifo_queue = true
  # content_based_deduplication = true
}

# Dead-letter queue
resource "aws_sqs_queue" "orders_dlq" {       # the DLQ
  name = "${local.name_prefix}-orders-dlq"   # the name
}

resource "aws_sqs_queue_redrive_policy" "orders" {   # the redrive policy
  queue_url = aws_sqs_queue.orders.id        # the source queue
  redrive_policy = jsonencode({               # the policy
    deadLetterTargetArn = aws_sqs_queue.orders_dlq.arn   # the DLQ
    maxReceiveCount     = 5                   # after 5 failed receives → DLQ
  })
}
```

### SNS (fan-out / pub-sub)

```hcl
resource "aws_sns_topic" "events" {           # an SNS topic
  name = "${local.name_prefix}-events"        # the name
}

resource "aws_sns_topic_subscription" "to_sqs" {   # a subscription
  topic_arn = aws_sns_topic.events.arn        # the topic
  protocol  = "sqs"                           # deliver to SQS
  endpoint  = aws_sqs_queue.orders.arn        # the SQS queue
  # filter_policy = { type = ["order.created"] }   # (optional) content filtering
}
```

### EventBridge (event bus — the glue)

```hcl
resource "aws_cloudwatch_event_rule" "s3_created" {   # an EventBridge rule
  name = "${local.name_prefix}-s3-created"   # the rule name
  event_pattern = jsonencode({                # the event pattern
    source = ["aws.s3"]                        # from S3
    detail_type = ["Object Created"]           # on object created
    detail = { bucket = [{ name = [aws_s3_bucket.app.bucket] }] }   # this bucket
  })
}

resource "aws_cloudwatch_event_target" "to_lambda" {   # the rule's target
  rule      = aws_cloudwatch_event_rule.s3_created.name   # the rule
  target_id = "handler"                              # a target id
  arn       = aws_lambda_function.handler.arn        # the Lambda
}
```

## 8.4 The Serverless Patterns

| Pattern | Services |
|---|---|
| **Event-driven** | S3/SNS/SQS/DynamoDB stream → Lambda |
| **API backend** | API Gateway → Lambda (± DynamoDB) |
| **Fan-out** | SNS → (SQS/Lambda/Email) |
| **Buffer/decouple** | producer → SQS → consumer |
| **Scheduled** | EventBridge Scheduler / CloudWatch Events → Lambda |
| **Stream processing** | Kinesis / DynamoDB stream → Lambda |

## 8.5 Getting It Right / Gotchas

- **`source_code_hash`** = required for updates to be detected (local zip / file).
- **Timeout**: memory and timeout are separate; a `timeout` too low = `Task timed out`.
- **Concurrency**: default 1000/account/region; use **reserved concurrency** to protect a function (or a table) from a runaway function.
- **VPC** = slower cold starts + needs NAT for internet.
- **Least privilege** on the execution role (it's in state; tighten `Resource`).
- **DLQ** on any SQS consumer (maxReceiveCount → DLQ).
- **Long polling** (`receive_wait_time_seconds`) reduces empty `ReceiveMessage`.
- **API GW → Lambda** needs a **lambda_permission** (the invoke grant).
- **arm64** = ~20% cheaper for the same compute.

## 8.6 Interview Quick Facts

- **Lambda** = functions (events), **ECS/Fargate** = containers, **EKS** = k8s, **EC2** = VMs.
- **Lambda execution role** = its permissions; **permissions** = who may invoke.
- **API GW** = HTTP front (HTTP API vs REST API).
- **SQS** = queue (buffer/decouple, DLQ, FIFO optional).
- **SNS** = pub/sub fan-out (filter policies).
- **EventBridge** = the event bus / rule engine (schedule + events).
- **VPC + Lambda** = private access, at a cold-start cost.
- **`source_code_hash`** is how Terraform knows the code changed.
