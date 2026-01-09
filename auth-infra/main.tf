# Rota: /api/* -> App Java (COM AUTHORIZER)
resource "aws_apigatewayv2_route" "app_route" {
  api_id    = aws_apigatewayv2_api.main_gateway.id
  route_key = "ANY /api/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.app_http_proxy.id}"

  # Aqui ligamos a proteção
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.auth_lambda_authorizer.id
}

# Rota Pública: Aprovação Externa (sem Authorizer)
# Permite que o cliente aprove a OS via link no email sem precisar logar
resource "aws_apigatewayv2_route" "external_approval_route" {
  api_id    = aws_apigatewayv2_api.main_gateway.id
  route_key = "GET /api/v1/aprovacao-externa"
  target    = "integrations/${aws_apigatewayv2_integration.app_http_proxy.id}"
}
