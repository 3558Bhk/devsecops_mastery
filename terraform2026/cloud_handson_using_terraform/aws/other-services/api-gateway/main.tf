# ============================================================================
#  API Gateway — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

data "aws_iam_policy_document" "assume" {        # the trust document
  statement {
    effect  = "Allow"                             # allow
    actions = ["sts:AssumeRole"]                  # the assume action
    principals {
      type        = "Service"                     # a service
      identifiers = ["lambda.amazonaws.com"]     # Lambda
    }
  }
}

resource "aws_iam_role" "fn" {                   # the role
  name               = "api-echo-role"           # the role's name
  assume_role_policy = data.aws_iam_policy_document.assume.json   # the trust document
}

data "aws_iam_policy" "logs" {                   # the logs policy
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"   # CloudWatch Logs
}

resource "aws_iam_role_policy_attachment" "logs" {   # attach logs
  role       = aws_iam_role.fn.id                # which role
  policy_arn = data.aws_iam_policy.logs.arn      # which policy
}

data "archive_file" "fn" {                       # zip the handler
  type        = "zip"                            # the format
  source_file = "${path.module}/echo.py"         # the file
  output_path = "${path.module}/build/echo.zip"  # where the zip goes
}

resource "aws_lambda_function" "echo" {          # the function
  function_name  = "api-echo"                    # the name
  role           = aws_iam_role.fn.arn           # the role
  runtime        = "python3.12"                  # the runtime
  handler        = "echo.handler"                # file.function
  filename       = data.archive_file.fn.output_path   # the zip
  source_code_hash = data.archive_file.fn.output_base64sha256   # redeploy on change
  timeout        = 10                            # max seconds
}

resource "aws_api_gateway_rest_api" "echo" {     # (1) THE API
  name = "echo-api"                              # the API's name

  endpoint_configuration {                        # where it's reachable
    types = ["EDGE"]                              # EDGE = public internet
  }
}

resource "aws_api_gateway_resource" "ping" {     # (2) THE PATH: /ping
  rest_api_id = aws_api_gateway_rest_api.echo.id # which API
  parent_id   = aws_api_gateway_rest_api.echo.root_resource_id   # under "/"
  path_part   = "ping"                             # → the path /ping
}

resource "aws_api_gateway_method" "ping_get" {   # (3) THE VERB: GET /ping
  rest_api_id = aws_api_gateway_rest_api.echo.id # which API
  resource_id = aws_api_gateway_resource.ping.id # which path
  http_method = "GET"                            # the verb
  authorization = "NONE"                         # open (add Cognito/Lambda authorizer for real auth)
  operation_name = "Ping"                        # a console-friendly name
}

resource "aws_api_gateway_integration" "ping_get" {   # (4) THE INTEGRATION: where GET goes
  rest_api_id = aws_api_gateway_rest_api.echo.id # which API
  resource_id = aws_api_gateway_resource.ping.id # which path
  http_method = "GET"                            # the verb

  type = "AWS_PROXY"                             # proxy: forward raw, parse raw
  uri  = aws_lambda_function.echo.invoke_arn     # the Lambda's invoke URL
}

resource "aws_api_gateway_deployment" "echo" {    # (5) THE DEPLOYMENT: make the API live
  rest_api_id = aws_api_gateway_rest_api.echo.id # which API
  stage_name  = "prod"                           # the stage it's published to
  description = "v1"                             # a note

  triggers = {                                    # re-deploy when anything changes
    lambda = aws_lambda_function.echo.arn         # the backend
  }
}
