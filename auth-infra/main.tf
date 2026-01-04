terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- DATA SOURCES ---

# Ler estado da REDE
data "aws_vpc" "existing_vpc" {
  tags = {
    Name = "${var.project_name}-budget-vpc"
  }
}

data "aws_subnets" "lambda_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing_vpc.id]
  }
  tags = {
    Name = "${var.project_name}-budget-public-subnet*" 
  }
}

# Ler estado do DATABASE (RDS)
data "terraform_remote_state" "database" {
  backend = "s3"
  config = {
    bucket = "fiap-oficinapro-kb-tfstate"
    key    = "oficinapro/database/terraform.tfstate"
    region = var.aws_region
  }
}

data "aws_security_group" "rds_sg" {
  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

# Ler estado do APP INFRA (EC2/K3s) para pegar o IP Público
data "terraform_remote_state" "app_infra" {
  backend = "s3"
  config = {
    bucket = "fiap-oficinapro-kb-tfstate"
    key    = "oficinapro/app-infra/terraform.tfstate"
    region = var.aws_region
  }
}

# --- IAM ROLE PARA LAMBDA ---

resource "aws_iam_role" "lambda_exec" {
  name = "${var.lambda_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# --- SECURITY GROUP DA LAMBDA ---

resource "aws_security_group" "lambda_sg" {
  name        = "${var.lambda_name}-sg"
  description = "Security Group para a Lambda de Auth"
  vpc_id      = data.aws_vpc.existing_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "rds_allow_lambda" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.lambda_sg.id
  security_group_id        = data.aws_security_group.rds_sg.id
  description              = "Permitir acesso da Lambda Auth"
}

# --- FUNÇÃO LAMBDA (AUTH) ---

# Arquivo placeholder se não existir
data "archive_file" "lambda_placeholder" {
  type        = "zip"
  output_path = "${path.module}/placeholder.zip"
  source {
    content  = "#!/bin/sh\necho 'placeholder'"
    filename = "bootstrap"
  }
}

resource "aws_lambda_function" "auth_function" {
  function_name = var.lambda_name
  role          = aws_iam_role.lambda_exec.arn
  handler       = "bootstrap"
  runtime       = "provided.al2023"
  timeout       = 10
  memory_size   = 128

  filename         = fileexists(var.lambda_zip_path) ? var.lambda_zip_path : data.archive_file.lambda_placeholder.output_path
  source_code_hash = fileexists(var.lambda_zip_path) ? filebase64sha256(var.lambda_zip_path) : data.archive_file.lambda_placeholder.output_base64sha256

  vpc_config {
    subnet_ids         = data.aws_subnets.lambda_subnets.ids
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      DB_HOST     = data.terraform_remote_state.database.outputs.db_instance_address
      DB_USER     = var.db_user
      DB_PASSWORD = var.db_password
      DB_NAME     = var.db_name
      DB_SSL_MODE = "require"
      JWT_SECRET  = var.jwt_secret
    }
  }
}

# --- API GATEWAY (CENTRALIZADOR) ---

resource "aws_apigatewayv2_api" "main_gateway" {
  name          = "oficinapro-api-gateway"
  protocol_type = "HTTP"
  description   = "API Gateway Principal (Auth, App, Pagamentos)"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main_gateway.id
  name        = "$default"
  auto_deploy = true
}

# --- AUTHORIZER (VALIDADOR DE TOKEN) ---

resource "aws_apigatewayv2_authorizer" "auth_lambda_authorizer" {
  api_id           = aws_apigatewayv2_api.main_gateway.id
  authorizer_type  = "REQUEST"
  authorizer_uri   = aws_lambda_function.auth_function.invoke_arn
  identity_sources = ["$request.header.Authorization"]
  name             = "oficinapro-auth-authorizer"
  authorizer_payload_format_version = "2.0"
  enable_simple_responses = true # Permite retornar booleano ou JSON simples
}

# --- INTEGRAÇÃO 1: AUTH (ROTA DE LOGIN) ---

resource "aws_apigatewayv2_integration" "auth_lambda_integration" {
  api_id           = aws_apigatewayv2_api.main_gateway.id
  integration_type = "AWS_PROXY"

  connection_type    = "INTERNET"
  description        = "Integração com Lambda Auth (Login)"
  integration_method = "POST"
  integration_uri    = aws_lambda_function.auth_function.invoke_arn
  payload_format_version = "2.0"
}

# Rota: /auth/* -> Lambda Auth (SEM AUTHORIZER, pois é login público)
resource "aws_apigatewayv2_route" "auth_route" {
  api_id    = aws_apigatewayv2_api.main_gateway.id
  route_key = "ANY /auth/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.auth_lambda_integration.id}"
}

# Rota exata para /auth (Login)
resource "aws_apigatewayv2_route" "auth_route_root" {
  api_id    = aws_apigatewayv2_api.main_gateway.id
  route_key = "POST /auth"
  target    = "integrations/${aws_apigatewayv2_integration.auth_lambda_integration.id}"
}

# Rota: /health -> Lambda Auth (Health Check)
resource "aws_apigatewayv2_route" "health_route" {
  api_id    = aws_apigatewayv2_api.main_gateway.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.auth_lambda_integration.id}"
}

# Permissão para o API Gateway invocar a Lambda (Login)
resource "aws_lambda_permission" "api_gw_auth" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main_gateway.execution_arn}/*/*"
}

# Permissão para o API Gateway invocar a Lambda (Authorizer)
resource "aws_lambda_permission" "api_gw_authorizer" {
  statement_id  = "AllowExecutionFromAPIGatewayAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main_gateway.execution_arn}/authorizers/${aws_apigatewayv2_authorizer.auth_lambda_authorizer.id}"
}

# --- VPC LINK (CONEXÃO SEGURA GATEWAY -> ALB) ---

resource "aws_security_group" "vpc_link_sg" {
  name        = "oficinapro-vpc-link-sg"
  description = "SG para o VPC Link do API Gateway"
  vpc_id      = data.aws_vpc.existing_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "oficinapro-vpc-link-sg" }
}

resource "aws_apigatewayv2_vpc_link" "app_vpc_link" {
  name               = "oficinapro-vpc-link"
  security_group_ids = [aws_security_group.vpc_link_sg.id]
  subnet_ids         = data.aws_subnets.lambda_subnets.ids # Usando subnets privadas/publicas disponíveis

  tags = { Name = "oficinapro-vpc-link" }
}

# --- INTEGRAÇÃO 2: APLICAÇÃO JAVA (VIA VPC LINK) ---

resource "aws_apigatewayv2_integration" "app_http_proxy" {
  api_id             = aws_apigatewayv2_api.main_gateway.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  
  # Conexão via VPC Link
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.app_vpc_link.id
  
  # URI aponta para o Listener do ALB
  integration_uri    = data.terraform_remote_state.app_infra.outputs.alb_listener_arn
  
  description        = "Proxy Privado para o App Java (VPC Link)"
}

# Rota: /api/* -> App Java (COM AUTHORIZER)
resource "aws_apigatewayv2_route" "app_route" {
  api_id    = aws_apigatewayv2_api.main_gateway.id
  route_key = "ANY /api/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.app_http_proxy.id}"
  
  # Aqui ligamos a proteção
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.auth_lambda_authorizer.id
}

# --- OUTPUTS ---

output "api_endpoint" {
  description = "URL do API Gateway Principal"
  value       = aws_apigatewayv2_api.main_gateway.api_endpoint
}

output "auth_lambda_arn" {
  value = aws_lambda_function.auth_function.arn
}
