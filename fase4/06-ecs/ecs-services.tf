# Task Execution Role (CloudWatch logs)
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

# CloudWatch Log Groups
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

# Task Definitions e Services (bootstrap - pipeline atualiza imagem)
resource "aws_ecs_task_definition" "bootstrap" {
  for_each                 = toset(local.ecs_services)
  family                   = each.value
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  cpu                      = "128"
  memory                   = "192"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([{
    name      = each.value
    image     = "public.ecr.aws/docker/library/busybox:latest"
    memory    = 192
    essential = true
    portMappings = [{
      containerPort = each.value == "payment" ? 8000 : 8082
      hostPort     = 0
      protocol     = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs[each.key].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
    command = ["sh", "-c", "sleep 3600"]
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
    weight           = 1
  }

  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  # Pipeline atualiza task definition via register-task-definition + update-service
  lifecycle {
    ignore_changes = [task_definition]
  }
}
