# Databases Infrastructure - Fase 4
# RDS PostgreSQL + DynamoDB

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
    key            = "fase4/databases/terraform.tfstate"
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

# DB Subnet Group
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group-fase4"
  subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet-group-fase4"
  }
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg-fase4"
  description = "Security group for RDS PostgreSQL databases"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.terraform_remote_state.network.outputs.vpc_cidr]
    description = "PostgreSQL access from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg-fase4"
  }
}

# RDS PostgreSQL - OS Database
resource "aws_db_instance" "os_db" {
  identifier = "${var.project_name}-os-db-fase4"

  engine         = "postgres"
  engine_version = "15.10"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp2"
  storage_encrypted     = false

  db_name  = "os_db"
  username = var.db_username
  password = var.db_password

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  backup_retention_period      = 1
  skip_final_snapshot          = true
  deletion_protection          = false
  publicly_accessible          = false
  performance_insights_enabled = false
  monitoring_interval          = 0

  tags = {
    Name    = "${var.project_name}-os-db-fase4"
    Service = "os-service"
  }
}

# RDS PostgreSQL - Billing Database
resource "aws_db_instance" "billing_db" {
  identifier = "${var.project_name}-billing-db-fase4"

  engine         = "postgres"
  engine_version = "15.10"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp2"
  storage_encrypted     = false

  db_name  = "billing_db"
  username = var.db_username
  password = var.db_password

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  backup_retention_period      = 1
  skip_final_snapshot          = true
  deletion_protection          = false
  publicly_accessible          = false
  performance_insights_enabled = false
  monitoring_interval          = 0

  tags = {
    Name    = "${var.project_name}-billing-db-fase4"
    Service = "billing-service"
  }
}

# RDS PostgreSQL - Execution Database
resource "aws_db_instance" "execution_db" {
  identifier = "${var.project_name}-execution-db-fase4"

  engine         = "postgres"
  engine_version = "15.10"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp2"
  storage_encrypted     = false

  db_name  = "execution_db"
  username = var.db_username
  password = var.db_password

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  backup_retention_period      = 1
  skip_final_snapshot          = true
  deletion_protection          = false
  publicly_accessible          = false
  performance_insights_enabled = false
  monitoring_interval          = 0

  tags = {
    Name    = "${var.project_name}-execution-db-fase4"
    Service = "execution-service"
  }
}

# RDS PostgreSQL - Customer Database
resource "aws_db_instance" "customer_db" {
  identifier = "${var.project_name}-customer-db-fase4"

  engine         = "postgres"
  engine_version = "15.10"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp2"
  storage_encrypted     = false

  db_name  = "customer_db"
  username = var.db_username
  password = var.db_password

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  backup_retention_period      = 1
  skip_final_snapshot          = true
  deletion_protection          = false
  publicly_accessible          = false
  performance_insights_enabled = false
  monitoring_interval          = 0

  tags = {
    Name    = "${var.project_name}-customer-db-fase4"
    Service = "customer-service"
  }
}

# RDS PostgreSQL - Saga Database
resource "aws_db_instance" "saga_db" {
  identifier = "${var.project_name}-saga-db-fase4"

  engine         = "postgres"
  engine_version = "15.10"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp2"
  storage_encrypted     = false

  db_name  = "saga_db"
  username = var.db_username
  password = var.db_password

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  backup_retention_period      = 1
  skip_final_snapshot          = true
  deletion_protection          = false
  publicly_accessible          = false
  performance_insights_enabled = false
  monitoring_interval          = 0

  tags = {
    Name    = "${var.project_name}-saga-db-fase4"
    Service = "saga-orchestrator"
  }
}

# DynamoDB Table - Billing Idempotency
resource "aws_dynamodb_table" "billing_idempotency" {
  name           = "${var.project_name}-billing-idempotency-fase4"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "idempotency_key"

  attribute {
    name = "idempotency_key"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name    = "${var.project_name}-billing-idempotency-fase4"
    Service = "billing-service"
  }
}

# DynamoDB Table - Payment Status Cache
resource "aws_dynamodb_table" "payment_status" {
  name           = "${var.project_name}-payment-status-fase4"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "payment_id"

  attribute {
    name = "payment_id"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name    = "${var.project_name}-payment-status-fase4"
    Service = "billing-service"
  }
}
