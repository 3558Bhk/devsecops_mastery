output "table_name" {                             # output: the table's name
  value       = aws_dynamodb_table.orders.name     # from the resource
  description = "Use with aws dynamodb put-item/get-item"   # how to test
}

output "table_arn" {                              # output: the table's ARN
  value       = aws_dynamodb_table.orders.arn      # the ARN
  description = "What the IAM policy scopes to"   # least privilege proof
}

output "env_param_name" {                         # output: the env parameter path
  value       = aws_ssm_parameter.env.name         # e.g. /datalab/app/env
  description = "aws ssm get-parameter --name <this>"   # how to read it
}

output "token_param_name" {                       # output: the SecureString parameter path
  value       = aws_ssm_parameter.api_token.name   # e.g. /datalab/app/api_token
  description = "aws ssm get-parameter --name <this> --with-decryption"   # needs the flag
}

output "secret_arn" {                             # output: the secret's ARN
  value       = aws_secretsmanager_secret.db_password.arn   # the ARN
  description = "aws secretsmanager get-secret-value --secret-id <this>"   # how to read it
}

output "role_arn" {                               # output: the app role
  value       = aws_iam_role.app.arn               # the ARN
  description = "Attach this to your EC2/Lambda; aws sts assume-role to test its limits"   # how to test
}

output "project" {                                # output: echo the project prefix
  value       = var.project                        # from the variable
  description = "Sanity check"                    # what it is
}
