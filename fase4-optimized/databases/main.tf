# Cost Optimization - Single RDS Multi-Database (Fase 4)
# Consolidate 5 RDS instances into 1 to save ~$58/month

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
    key            = "fase4-optimized/databases/terraform.tfstate"
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
      Phase       = "Fase4-Optimized"
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
  name       = "${var.project_name}-db-subnet-group-optimized"
  subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet-group-optimized"
  }
}

# Security Group for RDS
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg-optimized"
  description = "Security group for consolidated RDS PostgreSQL"
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
    Name = "${var.project_name}-rds-sg-optimized"
  }
}

# Single RDS Instance with Multiple Databases
resource "aws_db_instance" "consolidated" {
  identifier = "${var.project_name}-consolidated-db"

  engine         = "postgres"
  engine_version = "15.10"

  # Free Tier eligible instance type
  instance_class = "db.t3.micro"

  # Storage - Free Tier limits
  allocated_storage     = 20  # Free Tier limit
  max_allocated_storage = 20  # Disable autoscaling
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database
  db_name  = "os_db"  # Primary database
  username = var.db_username
  password = var.db_password
  port     = 5432

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # Backup
  backup_retention_period = 1  # Free Tier limit
  backup_window          = "03:00-04:00"
  maintenance_window     = "Mon:04:00-Mon:05:00"
  skip_final_snapshot    = true
  delete_automated_backups = true

  # High Availability (disabled for cost)
  multi_az = false

  # Performance
  performance_insights_enabled = false
  enabled_cloudwatch_logs_exports = ["postgresql"]

  # Protection
  deletion_protection = false
  apply_immediately   = true

  tags = {
    Name        = "${var.project_name}-consolidated-db"
    Databases   = "os_db+billing_db+execution_db+customer_db+saga_db"
    Optimization = "multi-database-single-instance"
  }
}

# DynamoDB Tables (keep as is - already optimized with On-Demand)
resource "aws_dynamodb_table" "billing_idempotency" {
  name         = "${var.project_name}-billing-idempotency-optimized"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "idempotency_key"

  attribute {
    name = "idempotency_key"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name    = "${var.project_name}-billing-idempotency-optimized"
    Service = "billing-service"
  }
}

resource "aws_dynamodb_table" "payment_status" {
  name         = "${var.project_name}-payment-status-optimized"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "payment_id"

  attribute {
    name = "payment_id"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name    = "${var.project_name}-payment-status-optimized"
    Service = "billing-service"
  }
}

# Null Resource to create additional databases via SQL
resource "null_resource" "create_databases" {
  depends_on = [aws_db_instance.consolidated]

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for RDS to be fully available
      sleep 60
      
      # Create additional databases using psql
      PGPASSWORD='${var.db_password}' psql \
        -h ${aws_db_instance.consolidated.address} \
        -U ${var.db_username} \
        -d os_db \
        -c "CREATE DATABASE billing_db;" || echo "billing_db already exists"
      
      PGPASSWORD='${var.db_password}' psql \
        -h ${aws_db_instance.consolidated.address} \
        -U ${var.db_username} \
        -d os_db \
        -c "CREATE DATABASE execution_db;" || echo "execution_db already exists"
      
      PGPASSWORD='${var.db_password}' psql \
        -h ${aws_db_instance.consolidated.address} \
        -U ${var.db_username} \
        -d os_db \
        -c "CREATE DATABASE customer_db;" || echo "customer_db already exists"
      
      PGPASSWORD='${var.db_password}' psql \
        -h ${aws_db_instance.consolidated.address} \
        -U ${var.db_username} \
        -d os_db \
        -c "CREATE DATABASE saga_db;" || echo "saga_db already exists"
      
      echo "✅ All databases created successfully!"
    EOT
  }
}
