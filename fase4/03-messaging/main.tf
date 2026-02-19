# Messaging Infrastructure - Fase 4
# Amazon SQS Queues

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
    key            = "fase4/messaging/terraform.tfstate"
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

# Dead Letter Queue (DLQ)
resource "aws_sqs_queue" "saga_dlq" {
  name                       = "${var.project_name}-saga-dlq.fifo"
  fifo_queue                 = true
  message_retention_seconds  = 1209600 # 14 days
  visibility_timeout_seconds = 300
  
  tags = {
    Name    = "${var.project_name}-saga-dlq"
    Purpose = "dead-letter-queue"
  }
}

# OS Service Queues
resource "aws_sqs_queue" "os_events" {
  name                        = "${var.project_name}-os-events.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 1209600
  visibility_timeout_seconds  = 300
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.saga_dlq.arn
    maxReceiveCount     = 3
  })
  
  tags = {
    Name    = "${var.project_name}-os-events"
    Service = "os-service"
  }
}

resource "aws_sqs_queue" "os_commands" {
  name                        = "${var.project_name}-os-commands.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 1209600
  visibility_timeout_seconds  = 300
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.saga_dlq.arn
    maxReceiveCount     = 3
  })
  
  tags = {
    Name    = "${var.project_name}-os-commands"
    Service = "os-service"
  }
}

# Billing Service Queues
resource "aws_sqs_queue" "billing_events" {
  name                        = "${var.project_name}-billing-events.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 1209600
  visibility_timeout_seconds  = 300
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.saga_dlq.arn
    maxReceiveCount     = 3
  })
  
  tags = {
    Name    = "${var.project_name}-billing-events"
    Service = "billing-service"
  }
}

resource "aws_sqs_queue" "billing_commands" {
  name                        = "${var.project_name}-billing-commands.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 1209600
  visibility_timeout_seconds  = 300
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.saga_dlq.arn
    maxReceiveCount     = 3
  })
  
  tags = {
    Name    = "${var.project_name}-billing-commands"
    Service = "billing-service"
  }
}

# Execution Service Queues
resource "aws_sqs_queue" "execution_events" {
  name                        = "${var.project_name}-execution-events.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 1209600
  visibility_timeout_seconds  = 300
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.saga_dlq.arn
    maxReceiveCount     = 3
  })
  
  tags = {
    Name    = "${var.project_name}-execution-events"
    Service = "execution-service"
  }
}

resource "aws_sqs_queue" "execution_commands" {
  name                        = "${var.project_name}-execution-commands.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 1209600
  visibility_timeout_seconds  = 300
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.saga_dlq.arn
    maxReceiveCount     = 3
  })
  
  tags = {
    Name    = "${var.project_name}-execution-commands"
    Service = "execution-service"
  }
}

# IAM Policy for SQS Access
resource "aws_iam_policy" "sqs_access" {
  name        = "${var.project_name}-sqs-access-fase4"
  description = "Policy for accessing SQS queues"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = [
          aws_sqs_queue.os_events.arn,
          aws_sqs_queue.os_commands.arn,
          aws_sqs_queue.billing_events.arn,
          aws_sqs_queue.billing_commands.arn,
          aws_sqs_queue.execution_events.arn,
          aws_sqs_queue.execution_commands.arn,
          aws_sqs_queue.saga_dlq.arn
        ]
      }
    ]
  })
  
  tags = {
    Name = "${var.project_name}-sqs-access"
  }
}
