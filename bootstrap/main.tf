# Este módulo cria os pré-requisitos para um backend Terraform S3.
# RODE-O PRIMEIRO!

terraform {
  required_version = ">= 1.0"
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

# Bucket S3 para armazenar o arquivo de estado (terraform.tfstate)
resource "aws_s3_bucket" "tfstate" {
  bucket = var.s3_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

# Ativar versionamento no bucket S3 para manter o histórico do estado
resource "aws_s3_bucket_versioning" "tfstate_versioning" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Ativar criptografia no lado do servidor para o bucket S3
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate_sse_config" {
  bucket = aws_s3_bucket.tfstate.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bloquear todo o acesso público ao bucket S3
resource "aws_s3_bucket_public_access_block" "tfstate_public_access" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Tabela DynamoDB para bloqueio de estado (evitar execuções concorrentes)
resource "aws_dynamodb_table" "tfstate_lock" {
  name           = var.dynamodb_table_name
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
