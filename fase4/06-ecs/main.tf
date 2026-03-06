# ECS Cluster - Fase 4 (alternativa ao EKS para Free Tier)
# 2x t3.micro = 2GB RAM total, sem custo de control plane
# Menos overhead que K8s = mais memória para containers

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
    key            = "fase4/ecs/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "oficinapro-tfstate-lock-table"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Phase       = "Fase4-ECS"
    }
  }
}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "fiap-oficinapro-ckm-tfstate"
    key    = "fase4/network/terraform.tfstate"
    region = "us-east-1"
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Name = "${var.cluster_name}-ecs"
  }
}

# IAM Role para instâncias EC2 (ECS Agent)
resource "aws_iam_role" "ecs_instance" {
  name = "${var.project_name}-ecs-instance-role-fase4"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ec2_container" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
  role       = aws_iam_role.ecs_instance.name
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "${var.project_name}-ecs-instance-profile-fase4"
  role = aws_iam_role.ecs_instance.name
}

# Security Group para instâncias ECS
resource "aws_security_group" "ecs_instances" {
  name        = "${var.project_name}-ecs-instances-fase4"
  description = "Security group for ECS EC2 container instances"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  # SSH (debug)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  # Tráfego entre instâncias (containers)
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
    description = "Inter-instance"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name = "${var.project_name}-ecs-instances-fase4"
  }
}

# ECS-optimized AMI (Amazon Linux 2)
data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# User data para registrar instância no cluster (AMI já tem ecs-init)
locals {
  ecs_user_data = <<-EOT
#!/bin/bash
echo ECS_CLUSTER=${aws_ecs_cluster.main.name} >> /etc/ecs/ecs.config
echo ECS_ENABLE_CONTAINER_METADATA=true >> /etc/ecs/ecs.config
echo ECS_ENABLE_TASK_CPU_MEM_LIMIT=true >> /etc/ecs/ecs.config
echo ECS_RESERVED_MEMORY=256 >> /etc/ecs/ecs.config
EOT
}

# Launch Template
resource "aws_launch_template" "ecs" {
  name_prefix   = "${var.project_name}-ecs-"
  image_id      = data.aws_ami.ecs_optimized.id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs_instance.arn
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ecs_instances.id]
  }

  user_data = base64encode(local.ecs_user_data)

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-ecs-instance"
    }
  }

  tags = {
    Name = "${var.project_name}-ecs-launch-template"
  }
}

# Auto Scaling Group - 2 instâncias
resource "aws_autoscaling_group" "ecs" {
  name                = "${var.project_name}-ecs-asg-fase4"
  vpc_zone_identifier = data.terraform_remote_state.network.outputs.public_subnet_ids
  desired_capacity    = var.desired_capacity
  min_size            = var.desired_capacity
  max_size            = var.desired_capacity

  launch_template {
    id      = aws_launch_template.ecs.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-ecs-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }
}

# Capacity provider EC2 (instâncias do ASG)
resource "aws_ecs_capacity_provider" "ec2" {
  name = "${var.project_name}-ec2-fase4"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs.arn
    managed_termination_protection = "DISABLED"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = [aws_ecs_capacity_provider.ec2.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
    base              = 0
  }
}

# SSM Parameters para pipelines
resource "aws_ssm_parameter" "cluster_name" {
  name  = "/oficinapro/ecs/cluster-name"
  type  = "String"
  value = aws_ecs_cluster.main.name
  tags  = { Phase = "Fase4-ECS" }
}

resource "aws_ssm_parameter" "task_execution_role_arn" {
  name  = "/oficinapro/ecs/task-execution-role-arn"
  type  = "String"
  value = aws_iam_role.ecs_task_execution.arn
  tags  = { Phase = "Fase4-ECS" }
}

# --- Task Execution Role (CloudWatch logs) ---
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-ecs-task-execution-fase4"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.ecs_task_execution.name
}

# --- CloudWatch Log Groups ---
locals {
  ecs_services = [
    "saga-orchestrator",
    "billing",
    "execution",
    "customer",
    "payment",
    "core-domain"
  ]
}

resource "aws_cloudwatch_log_group" "ecs" {
  for_each          = toset(local.ecs_services)
  name              = "/ecs/${each.value}"
  retention_in_days = 7
}

# --- Task Definitions e Services (bootstrap - pipeline atualiza imagem) ---
resource "aws_ecs_task_definition" "bootstrap" {
  for_each                 = toset(local.ecs_services)
  family                   = each.value
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = "128"
  memory                   = "192"
  execution_role_arn        = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name      = each.value
    image     = "public.ecr.aws/docker/library/busybox:latest"
    memory    = 192
    essential = true
    portMappings = [{
      containerPort = 8080
      hostPort      = 0
      protocol      = "tcp"
    }]
    command = ["sh", "-c", "sleep 3600"]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs[each.key].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "main" {
  for_each        = toset(local.ecs_services)
  name            = each.value
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.bootstrap[each.key].arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.ec2.name
    weight            = 1
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent        = 100
}
