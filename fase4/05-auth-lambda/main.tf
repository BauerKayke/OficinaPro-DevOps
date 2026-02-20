# Auth Lambda Infrastructure - Fase 4
# Lambda + API Gateway

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    bucket         = "fiap-oficinapro-ckm-tfstate"
    key            = "fase4/auth-lambda/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "oficinapro-tfstate-lock-table"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "OficinaPro"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Phase       = "Fase4"
    }
  }
}

# Remote state from network
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "fiap-oficinapro-ckm-tfstate"
    key    = "fase4/network/terraform.tfstate"
    region = "us-east-1"
  }
}

# Remote state from databases
data "terraform_remote_state" "databases" {
  backend = "s3"
  config = {
    bucket = "fiap-oficinapro-ckm-tfstate"
    key    = "fase4-optimized/databases/terraform.tfstate"
    region = "us-east-1"
  }
}

# Security Group for Lambda
resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-auth-lambda-sg-fase4"
  description = "Security group for Auth Lambda function"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-auth-lambda-sg-fase4"
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-auth-lambda-role-fase4"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-auth-lambda-role"
  }
}

# Attach VPC execution policy
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Attach basic execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Function
resource "aws_lambda_function" "auth" {
  function_name = "${var.project_name}-auth-function-fase4"
  role          = aws_iam_role.lambda.arn
  handler       = "bootstrap"
  runtime       = "provided.al2023"

  # Placeholder - você precisará fazer build e upload do código Go
  filename         = var.lambda_zip_path
  source_code_hash = fileexists(var.lambda_zip_path) ? filebase64sha256(var.lambda_zip_path) : ""

  memory_size = 256
  timeout     = 30

  vpc_config {
    subnet_ids         = data.terraform_remote_state.network.outputs.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_HOST           = split(":", data.terraform_remote_state.databases.outputs.consolidated_db_endpoint)[0]
      DB_PORT           = "5432"
      DB_NAME           = "os_db"
      DB_USER           = var.db_username
      DB_PASSWORD       = var.db_password
      JWT_SECRET        = var.jwt_secret
      JWT_ISSUER        = "auth-oficinapro-fase4"
      JWT_EXPIRATION    = "3600"
      ENVIRONMENT       = var.environment
      NEW_RELIC_LICENSE_KEY = var.new_relic_license_key
    }
  }

  tags = {
    Name = "${var.project_name}-auth-function-fase4"
  }
}

# Lambda Permission for API Gateway
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.auth.execution_arn}/*/*"
}

# API Gateway HTTP API
resource "aws_apigatewayv2_api" "auth" {
  name          = "${var.project_name}-auth-api-fase4"
  protocol_type = "HTTP"
  description   = "Auth API Gateway for Fase 4"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["*"]
    max_age       = 300
  }

  tags = {
    Name = "${var.project_name}-auth-api"
  }
}

# API Gateway Integration
resource "aws_apigatewayv2_integration" "auth" {
  api_id           = aws_apigatewayv2_api.auth.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.auth.invoke_arn
  
  payload_format_version = "2.0"
}

# API Gateway Route - POST /auth
resource "aws_apigatewayv2_route" "auth_post" {
  api_id    = aws_apigatewayv2_api.auth.id
  route_key = "POST /auth"
  target    = "integrations/${aws_apigatewayv2_integration.auth.id}"
}

# API Gateway Route - POST /auth/validate
resource "aws_apigatewayv2_route" "auth_validate" {
  api_id    = aws_apigatewayv2_api.auth.id
  route_key = "POST /auth/validate"
  target    = "integrations/${aws_apigatewayv2_integration.auth.id}"
}

# API Gateway Route - GET /health
resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.auth.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.auth.id}"
}

# API Gateway Stage
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.auth.id
  name        = "$default"
  auto_deploy = true

  tags = {
    Name = "${var.project_name}-auth-api-stage"
  }
}
