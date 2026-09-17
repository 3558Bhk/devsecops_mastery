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

# ── 1. THE DATABASE: DynamoDB (schemaless, millisecond reads/writes) ──────────

resource "aws_dynamodb_table" "orders" {         # the table
  name         = "${var.project}-orders"         # unique per region
  billing_mode = "PAY_PER_REQUEST"               # pay per use (free-tier friendly)

  hash_key = "order_id"                          # the partition key

  attribute {                                    # declare the partition key's type
    name = "order_id"                            # same as hash_key
    type = "S"                                   # string
  }

  attribute {                                    # declare the GSI key's type
    name = "status"                              # the attribute we index
    type = "S"                                   # string
  }

  global_secondary_index {                        # a GSI: a second view, keyed by status
    name            = "StatusIndex"               # the index name
    projection_type = "ALL"                       # include all attributes in results
    hash_key        = "status"                    # so "WHERE status = 'new'" is a fast Query
  }
}

# ── 2. THE IDENTITY: a Lambda role scoped to THIS table only ──────────────────

data "aws_iam_policy_document" "assume" {        # who may assume the role
  statement {
    effect  = "Allow"                             # allow
    actions = ["sts:AssumeRole"]                  # the assume action
    principals {                                    # by whom:
      type        = "Service"                     # a service
      identifiers = ["lambda.amazonaws.com"]     # Lambda
    }
  }
}

resource "aws_iam_role" "orders_api" {           # the role the API function runs as
  name               = "${var.project}-orders-role"   # unique name
  assume_role_policy = data.aws_iam_policy_document.assume.json   # from the document
}

data "aws_iam_policy" "lambda_exec" {            # AWS's built-in "may write logs" policy
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"   # CloudWatch Logs
}

resource "aws_iam_role_policy_attachment" "lambda_exec" {   # attach log permissions
  role       = aws_iam_role.orders_api.id        # which role
  policy_arn = data.aws_iam_policy.lambda_exec.arn   # which policy
}

resource "aws_iam_role_policy" "table_access" {  # the CUSTOM part: only THIS table
  name = "orders-table-only"                     # the policy's name (on the role)
  role = aws_iam_role.orders_api.id              # which role

  policy = jsonencode({                          # the policy as JSON
    Version = "2012-10-17"                        # policy version
    Statement = [{                                 # one statement
      Effect = "Allow"                             # allow
      Actions = [                                   # the DynamoDB operations an API uses
        "dynamodb:PutItem",                        # write one item
        "dynamodb:GetItem",                        # read one item
        "dynamodb:Query",                          # query (table or GSI)
        "dynamodb:Scan"                            # full scan
      ]
      Resource = [                                  # ONLY this table (+ its index):
        aws_dynamodb_table.orders.arn,              # the table
        "${aws_dynamodb_table.orders.arn}/index/*"  # its indexes
      ]
    }]
  })
}

# ── 3. THE WORKER: one Lambda serving both methods ────────────────────────────

data "archive_file" "orders_api" {               # zip the api/ folder (Terraform does the packaging)
  type        = "zip"                            # the format
  source_dir  = "${path.module}/api"             # the folder with orders.py
  output_path = "${path.module}/build/orders-api.zip"   # where the zip goes
}

resource "aws_lambda_function" "orders_api" {    # the function
  function_name  = "${var.project}-orders-api"   # unique name
  role           = aws_iam_role.orders_api.arn   # run as this role
  runtime        = "python3.12"                  # language + version
  handler        = "orders.handler"              # file.function inside the zip
  filename       = data.archive_file.orders_api.output_path   # the zipped code
  source_code_hash = data.archive_file.orders_api.output_base64sha256   # redeploy on code change
  timeout        = 10                            # max seconds per request

  environment {                                   # environment variables for the function
    variables = {                                   # the map of name → value
      ORDERS_TABLE = aws_dynamodb_table.orders.name   # which table to use
    }
  }
}

# ── 4. THE GATEWAY: a public REST API in front of the Lambda ──────────────────

resource "aws_api_gateway_rest_api" "orders" {   # the API itself
  name = "${var.project}-orders-rest"            # the API's name

  endpoint_configuration {                        # where the API is reachable
    types = ["EDGE"]                              # EDGE = public internet (PRIVATE = VPC only)
  }
}

resource "aws_api_gateway_resource" "orders" {   # the /orders path (a child of the root resource)
  rest_api_id = aws_api_gateway_rest_api.orders.id   # which API
  parent_id   = aws_api_gateway_rest_api.orders.root_resource_id   # under "/"
  path_part   = "orders"                             # → the path becomes /orders
}

# POST /orders → the Lambda (the write path)
resource "aws_api_gateway_method" "orders_post" {   # declare the method on the resource
  rest_api_id = aws_api_gateway_rest_api.orders.id  # which API
  resource_id = aws_api_gateway_resource.orders.id  # which path
  http_method = "POST"                             # the verb
  authorization = "NONE"                           # open API (add a Lambda authorizer in real life!)

  operation_name = "CreateOrder"                   # a name shown in the API console
}

resource "aws_api_gateway_integration" "orders_post" {   # where POST actually goes
  rest_api_id = aws_api_gateway_rest_api.orders.id   # which API
  resource_id = aws_api_gateway_resource.orders.id   # which path
  http_method = "POST"                             # the verb

  type = "AWS_PROXY"                               # proxy mode: forward the raw event, parse the raw response
  uri  = aws_lambda_function.orders_api.invoke_arn # the Lambda's invoke URL

  timeout_milliseconds = 10000                     # match the Lambda's 10s timeout
}

# GET /orders → the same Lambda (the read path)
resource "aws_api_gateway_method" "orders_get" {    # declare GET
  rest_api_id = aws_api_gateway_rest_api.orders.id  # which API
  resource_id = aws_api_gateway_resource.orders.id  # which path
  http_method = "GET"                              # the verb
  authorization = "NONE"                           # open API
  operation_name = "ListOrders"                    # a name for the console
}

resource "aws_api_gateway_integration" "orders_get" {   # where GET actually goes
  rest_api_id = aws_api_gateway_rest_api.orders.id   # which API
  resource_id = aws_api_gateway_resource.orders.id   # which path
  http_method = "GET"                              # the verb
  type = "AWS_PROXY"                               # proxy mode
  uri  = aws_lambda_function.orders_api.invoke_arn # the same Lambda
  timeout_milliseconds = 10000                     # same timeout
}

# OPTIONS on "/" → CORS for browsers (a mock integration: no backend needed)
resource "aws_api_gateway_method" "root_options" {  # the preflight method on the ROOT resource
  rest_api_id = aws_api_gateway_rest_api.orders.id  # which API
  resource_id = aws_api_gateway_rest_api.orders.root_resource_id   # the root ("/")
  http_method = "OPTIONS"                           # the CORS preflight verb
  authorization = "NONE"                           # always open
}

resource "aws_api_gateway_integration" "root_options" {   # a MOCK integration = "return this canned answer"
  rest_api_id = aws_api_gateway_rest_api.orders.id   # which API
  resource_id = aws_api_gateway_rest_api.orders.root_resource_id   # the root
  http_method = "OPTIONS"                           # the verb

  type = "MOCK"                                    # no backend — just return a template
  request_templates = {                             # what to return (keyed by content type)
    "application/json" = jsonencode({               # a 200 with the CORS headers browsers need
      statusCode = 200
      headers    = {                                 # (single quotes are literal — the CORS spec wants them)
        "Access-Control-Allow-Origin"  = "'*'"
        "Access-Control-Allow-Methods" = "'POST, GET, OPTIONS'"
        "Access-Control-Allow-Headers" = "'Content-Type, Authorization'"
      }
    })
  }
}

# The DEPLOYMENT: API Gateway only serves what was "released"
resource "aws_api_gateway_deployment" "orders" {    # snapshot the current API definition
  rest_api_id = aws_api_gateway_rest_api.orders.id  # which API
  stage_name  = "dev"                               # ...and expose it as the stage "dev"
  description = "order api v1"                      # a human label

  triggers = {                                      # re-deploy automatically when...
    lambda = aws_lambda_function.orders_api.arn     # ...the Lambda changes (any change to the API re-triggers too)
  }
}
