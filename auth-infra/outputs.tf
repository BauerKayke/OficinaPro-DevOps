# Output do Security Group do VPC Link (usado pelo app-infra para permitir tráfego no ALB)
output "vpc_link_sg_id" {
  description = "ID do Security Group usado pelo VPC Link do API Gateway"
  value       = aws_security_group.lambda_sg.id
}

# Output do VPC Link ID
output "vpc_link_id" {
  description = "ID do VPC Link do API Gateway"
  value       = aws_apigatewayv2_vpc_link.alb_link.id
}

# Output do API Gateway URL
output "api_gateway_url" {
  description = "URL do API Gateway"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

# Output da Lambda Function ARN
output "lambda_function_arn" {
  description = "ARN da função Lambda de autenticação"
  value       = aws_lambda_function.auth_lambda.arn
}
