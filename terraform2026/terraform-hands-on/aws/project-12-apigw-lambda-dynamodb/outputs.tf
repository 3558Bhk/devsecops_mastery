output "invoke_url" {                             # output: the public URL of the /orders endpoint
  value       = "https://${aws_api_gateway_rest_api.orders.id}.execute-api.${var.region}.amazonaws.com/dev/orders"   # the stage URL + path
  description = "POST an order JSON here; GET returns all orders"   # how to use it
}

output "table_name" {                             # output: the DynamoDB table
  value       = aws_dynamodb_table.orders.name     # the name
  description = "aws dynamodb scan --table-name <this>"   # how to peek at the data
}

output "lambda_name" {                            # output: the function
  value       = aws_lambda_function.orders_api.function_name   # the name
  description = "Watch its logs in CloudWatch"    # when a request misbehaves
}
