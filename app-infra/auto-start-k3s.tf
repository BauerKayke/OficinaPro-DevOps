# ============================================================================
# Auto Start K3s Master - Solução On-Demand para Spot Instance
# ============================================================================
# 
# Esta solução permite que a K3s Master Spot Instance seja iniciada
# automaticamente apenas quando houver requisições, economizando custos.
#
# Funcionamento:
# 1. ALB detecta que não há targets saudáveis (503 Service Unavailable)
# 2. Lambda é acionada para iniciar a Spot Instance
# 3. Instância sobe, K3s inicializa, e se registra no Target Group
# 4. Após período de inatividade (configur��vel), instância é parada
#
# Economia estimada: ~$18/mês (apenas ~6h/dia de uso)
# ============================================================================

# ----------------------------------------------------------------------------
# 1. Lambda Role para gerenciar EC2
# ----------------------------------------------------------------------------
resource "aws_iam_role" "k3s_auto_start_lambda_role" {
  name = "fiap-oficinapro-k3s-auto-start-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "fiap-oficinapro-k3s-auto-start-role"
  }
}

# Política para gerenciar EC2 e Auto Scaling
resource "aws_iam_role_policy" "k3s_auto_start_policy" {
  name = "k3s-auto-start-policy"
  role = aws_iam_role.k3s_auto_start_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:DescribeInstanceStatus",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:DescribeAutoScalingGroups",
          "elasticloadbalancing:DescribeTargetHealth",
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# ----------------------------------------------------------------------------
# 2. Lambda Function - Auto Start K3s
# ----------------------------------------------------------------------------
resource "aws_lambda_function" "k3s_auto_start" {
  filename      = "${path.module}/lambda/k3s-auto-start.zip"
  function_name = "fiap-oficinapro-k3s-auto-start"
  role          = aws_iam_role.k3s_auto_start_lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 60

  environment {
    variables = {
      ASG_NAME           = aws_autoscaling_group.k3s_master_asg.name
      TARGET_GROUP_ARN   = aws_lb_target_group.app_tg.arn
      INSTANCE_TAG_NAME  = "fiap-oficinapro-kb-k3s-master-spot"
    }
  }

  tags = {
    Name = "fiap-oficinapro-k3s-auto-start"
  }
}

# ----------------------------------------------------------------------------
# 3. EventBridge Rule - Acionar Lambda quando ALB não tem targets
# ----------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "alb_no_targets" {
  name        = "fiap-oficinapro-alb-no-healthy-targets"
  description = "Aciona Lambda quando ALB não tem targets saudáveis"

  event_pattern = jsonencode({
    source      = ["aws.elasticloadbalancing"]
    detail-type = ["AWS API Call via CloudTrait"]
    detail = {
      eventName = ["TargetFailure"]
      requestParameters = {
        targetGroupArn = [aws_lb_target_group.app_tg.arn]
      }
    }
  })

  tags = {
    Name = "fiap-oficinapro-alb-no-targets"
  }
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.alb_no_targets.name
  target_id = "K3sAutoStartLambda"
  arn       = aws_lambda_function.k3s_auto_start.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.k3s_auto_start.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.alb_no_targets.arn
}

# ----------------------------------------------------------------------------
# 4. CloudWatch Alarm - Auto Stop após inatividade
# ----------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "k3s_low_activity" {
  alarm_name          = "fiap-oficinapro-k3s-low-activity"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "RequestCount"
  namespace           = "AWS/ApplicationELB"
  period              = "600" # 10 minutos
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Para K3s Master após 30 minutos de inatividade"
  treat_missing_data  = "breaching"

  dimensions = {
    LoadBalancer = aws_lb.app_alb.arn_suffix
  }

  alarm_actions = [aws_sns_topic.k3s_auto_stop.arn]

  tags = {
    Name = "fiap-oficinapro-k3s-low-activity"
  }
}

# SNS Topic para auto stop
resource "aws_sns_topic" "k3s_auto_stop" {
  name = "fiap-oficinapro-k3s-auto-stop"

  tags = {
    Name = "fiap-oficinapro-k3s-auto-stop"
  }
}

# Lambda para parar instância
resource "aws_lambda_function" "k3s_auto_stop" {
  filename      = "${path.module}/lambda/k3s-auto-stop.zip"
  function_name = "fiap-oficinapro-k3s-auto-stop"
  role          = aws_iam_role.k3s_auto_start_lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 30

  environment {
    variables = {
      ASG_NAME          = aws_autoscaling_group.k3s_master_asg.name
      INSTANCE_TAG_NAME = "fiap-oficinapro-kb-k3s-master-spot"
    }
  }

  tags = {
    Name = "fiap-oficinapro-k3s-auto-stop"
  }
}

resource "aws_sns_topic_subscription" "lambda_auto_stop" {
  topic_arn = aws_sns_topic.k3s_auto_stop.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.k3s_auto_stop.arn
}

resource "aws_lambda_permission" "allow_sns_auto_stop" {
  statement_id  = "AllowExecutionFromSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.k3s_auto_stop.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.k3s_auto_stop.arn
}

# ----------------------------------------------------------------------------
# 5. Auto Scaling Group para K3s Master (min=0, max=1)
# ----------------------------------------------------------------------------
resource "aws_launch_template" "k3s_master" {
  name_prefix   = "fiap-oficinapro-k3s-master-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2_profile.arn
  }

  key_name = aws_key_pair.budget_key.key_name

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.k3s_cluster_sg.id]
    delete_on_termination       = true
  }

  user_data = base64encode(templatefile("${path.module}/scripts/user_data_master.sh.tpl", {
    cluster_token = var.k3s_cluster_token
    rds_endpoint  = data.terraform_remote_state.database.outputs.rds_endpoint
  }))

  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price          = "0.080"
      spot_instance_type = "one-time"
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name           = "fiap-oficinapro-kb-k3s-master-spot"
      Role           = "master"
      Type           = "spot"
      CostOptimized  = "true"
      AutoManaged    = "true"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "k3s_master_asg" {
  name                = "fiap-oficinapro-k3s-master-asg"
  vpc_zone_identifier = data.terraform_remote_state.network.outputs.public_subnet_ids
  target_group_arns   = [aws_lb_target_group.app_tg.arn]
  health_check_type   = "ELB"
  health_check_grace_period = 300

  min_size         = 0  # Não roda por padrão
  max_size         = 1
  desired_capacity = 0  # Inicia com 0 instâncias

  launch_template {
    id      = aws_launch_template.k3s_master.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "fiap-oficinapro-k3s-master-asg"
    propagate_at_launch = false
  }

  tag {
    key                 = "AutoManaged"
    value               = "true"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

# ----------------------------------------------------------------------------
# 6. Outputs
# ----------------------------------------------------------------------------
output "auto_start_lambda_arn" {
  description = "ARN da Lambda que inicia K3s automaticamente"
  value       = aws_lambda_function.k3s_auto_start.arn
}

output "auto_stop_lambda_arn" {
  description = "ARN da Lambda que para K3s após inatividade"
  value       = aws_lambda_function.k3s_auto_stop.arn
}

output "asg_name" {
  description = "Nome do Auto Scaling Group"
  value       = aws_autoscaling_group.k3s_master_asg.name
}

output "k3s_management_instructions" {
  description = "Instruções para gerenciar K3s manualmente"
  value       = <<-EOT
    # Iniciar K3s manualmente:
    aws autoscaling set-desired-capacity --auto-scaling-group-name ${aws_autoscaling_group.k3s_master_asg.name} --desired-capacity 1

    # Parar K3s manualmente:
    aws autoscaling set-desired-capacity --auto-scaling-group-name ${aws_autoscaling_group.k3s_master_asg.name} --desired-capacity 0

    # Verificar status:
    aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${aws_autoscaling_group.k3s_master_asg.name}

    # Ver logs da Lambda (auto start):
    aws logs tail /aws/lambda/${aws_lambda_function.k3s_auto_start.function_name} --follow

    # Ver logs da Lambda (auto stop):
    aws logs tail /aws/lambda/${aws_lambda_function.k3s_auto_stop.function_name} --follow
  EOT
}
