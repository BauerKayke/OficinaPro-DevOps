output "lambda_function_name" {
  description = "Auth Lambda function name"
  value       = aws_lambda_function.auth.function_name
}

output "lambda_function_arn" {
  description = "Auth Lambda function ARN"
  value       = aws_lambda_function.auth.arn
}

output "api_gateway_url" {
  description = "API Gateway endpoint URL"
  value       = aws_apigatewayv2_api.auth.api_endpoint
}

output "api_gateway_id" {
  description = "API Gateway ID"
  value       = aws_apigatewayv2_api.auth.id
}

output "lambda_security_group_id" {
  description = "Lambda security group ID"
  value       = aws_security_group.lambda.id
}
