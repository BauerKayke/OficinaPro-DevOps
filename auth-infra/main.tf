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

# --- DATA SOURCES (Integração com a Rede Existente) ---

data "aws_vpc" "existing_vpc" {
  tags = {
    Name = "${var.project_name}-budget-vpc"
  }
}

# Buscando subnets privadas para a Lambda (segurança)
# Assumindo que o app-infra cria subnets privadas ou usaremos as públicas se for uma VPC simples
# Para este setup Free Tier, vamos usar as subnets que temos disponíveis.
data "aws_subnets" "lambda_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing_vpc.id]
  }
  # Ajuste o filtro de tag conforme o que foi criado no app-infra
  # No app-infra criamos "budget-public-subnet". A Lambda pode rodar lá se tiver acesso ao RDS.
  tags = {
    Name = "${var.project_name}-budget-public-subnet*" 
  }
}

data "aws_security_group" "rds_sg" {
  tags = {
    Name = "${var.project_name}-rds-sg"
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

# Permissão básica para logs
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Permissão para rodar dentro da VPC (criar interfaces de rede)
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# --- SECURITY GROUP DA LAMBDA ---

resource "aws_security_group" "lambda_sg" {
  name        = "${var.lambda_name}-sg"
  description = "Security Group para a Lambda de Auth"
  vpc_id      = data.aws_vpc.existing_vpc.id

  # Saída liberada (para acessar RDS e Internet)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Atualizar SG do RDS para permitir acesso da Lambda
resource "aws_security_group_rule" "rds_allow_lambda" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.lambda_sg.id
  security_group_id        = data.aws_security_group.rds_sg.id
  description              = "Permitir acesso da Lambda Auth"
}

# --- FUNÇÃO LAMBDA ---

# Arquivo placeholder se não existir (para o plan inicial funcionar)
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
  handler       = "bootstrap" # Para provided.al2023, o handler é ignorado mas o binário deve ser 'bootstrap'
  runtime       = "provided.al2023" # Amazon Linux 2023 (sucessor do go1.x)
  timeout       = 10
  memory_size   = 128

  # Usa o arquivo real se existir, senão usa o placeholder
  filename         = fileexists(var.lambda_zip_path) ? var.lambda_zip_path : data.archive_file.lambda_placeholder.output_path
  source_code_hash = fileexists(var.lambda_zip_path) ? filebase64sha256(var.lambda_zip_path) : data.archive_file.lambda_placeholder.output_base64sha256

  vpc_config {
    subnet_ids         = data.aws_subnets.lambda_subnets.ids
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      DB_HOST     = var.db_host
      DB_USER     = var.db_user
      DB_PASSWORD = var.db_password
      DB_NAME     = var.db_name
      JWT_SECRET  = var.jwt_secret
    }
  }
}

# --- API GATEWAY (HTTP API) ---

resource "aws_apigatewayv2_api" "auth_api" {
  name          = "oficinapro-auth-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.auth_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.auth_api.id
  integration_type = "AWS_PROXY"

  connection_type      = "INTERNET"
  description          = "Integração com Lambda Auth"
  integration_method   = "POST"
  integration_uri      = aws_lambda_function.auth_function.invoke_arn
  payload_format_version = "2.0"
}

# Rota padrão: envia tudo para a Lambda
resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.auth_api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Permissão para o API Gateway invocar a Lambda
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.auth_api.execution_arn}/*/*"
}

# --- OUTPUTS ---

output "api_endpoint" {
  description = "URL do API Gateway"
  value       = aws_apigatewayv2_api.auth_api.api_endpoint
}

