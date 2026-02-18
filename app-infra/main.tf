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

# --- DATA SOURCES: LER ESTADOS ---

# Lê o estado da REDE (VPC, Subnets)
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "fiap-oficinapro-ckm-tfstate"
    key    = "oficinapro/network/terraform.tfstate"
    region = var.aws_region
  }
}

# Lê o estado do BANCO (Endpoint)
data "terraform_remote_state" "database" {
  backend = "s3"
  config = {
    bucket = "fiap-oficinapro-ckm-tfstate"
    key    = "oficinapro/database/terraform.tfstate"
    region = var.aws_region
  }
}

# Data sources locais
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# --- APPLICATION LOAD BALANCER (ALB) ---

# Security Group do ALB (Permite HTTP/HTTPS da VPC interna)
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Security Group for internal ALB - accepts VPC traffic"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  # ALB INTERNO - aceita tráfego da VPC (para VPC Link do API Gateway)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]  # Tráfego da VPC
    description = "HTTP da VPC (VPC Link)"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]  # Tráfego da VPC
    description = "HTTPS da VPC (VPC Link)"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}

# ALB Interno
resource "aws_lb" "app_alb" {
  name               = "${var.project_name}-alb"
  internal           = true  # Interno para funcionar com VPC Link usando Listener ARN
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.terraform_remote_state.network.outputs.public_subnet_ids

  enable_deletion_protection = false

  tags = { Name = "${var.project_name}-alb" }
}

# Target Group (Aponta para EC2 na porta 80 - Nginx HostNetwork)
resource "aws_lb_target_group" "app_tg" {
  name     = "${var.project_name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.terraform_remote_state.network.outputs.vpc_id

  health_check {
    path                = "/api/v1/actuator/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = { Name = "${var.project_name}-tg" }
}

# Listener HTTP (Porta 80)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# Associação das instâncias ao Target Group (ambas)
resource "aws_lb_target_group_attachment" "master_attach" {
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.k3s_master.id
  port             = 80
}

# --- IAM ROLE E INSTANCE PROFILE PARA EC2 (SSM + ECR) ---

# IAM Role para a instância EC2
resource "aws_iam_role" "ec2_ssm_role" {
  name = "${var.project_name}-k3s-role-fase4"

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

  tags = { Name = "${var.project_name}-k3s-role-fase4" }
}

# Anexar política gerenciada AmazonSSMManagedInstanceCore
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Anexar política para ECR (ReadOnly)
resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Política inline para SQS (Billing Service)
resource "aws_iam_role_policy" "sqs_access" {
  name = "${var.project_name}-sqs-access"
  role = aws_iam_role.ec2_ssm_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:CreateQueue",
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes",
          "sqs:SetQueueAttributes",
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:DeleteQueue",
          "sqs:ListQueues"
        ]
        Resource = "arn:aws:sqs:${var.aws_region}:*:oficinapro-*"
      }
    ]
  })
}

# Instance Profile (conecta a Role às instâncias EC2)
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-k3s-profile-fase4"
  role = aws_iam_role.ec2_ssm_role.name

  tags = { Name = "${var.project_name}-k3s-profile-fase4" }
}

# --- SECURITY GROUP PARA K3S CLUSTER (2 NODES) ---

# Security Group para K3s Cluster
resource "aws_security_group" "k3s_cluster_sg" {
  name        = "${var.project_name}-k3s-cluster-sg"
  description = "Security group para cluster K3s (master + worker)"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  tags = { Name = "${var.project_name}-k3s-cluster-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

# Regra: SSH liberado (necessário para CI/CD)
resource "aws_security_group_rule" "ingress_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k3s_cluster_sg.id
  description       = "SSH para CI/CD"
}

# Regra: K3s API Server (6443) - Master exposto
resource "aws_security_group_rule" "ingress_k3s_api" {
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k3s_cluster_sg.id
  description       = "K3s API server"
}

# Regra: HTTP (80) APENAS do ALB
resource "aws_security_group_rule" "ingress_http_from_alb" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id
  security_group_id        = aws_security_group.k3s_cluster_sg.id
  description              = "HTTP apenas via ALB"
}

# Regra: HTTPS (443) APENAS do ALB
resource "aws_security_group_rule" "ingress_https_from_alb" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id
  security_group_id        = aws_security_group.k3s_cluster_sg.id
  description              = "HTTPS apenas via ALB"
}

# Regra: Comunicação Interna K3s (self) - Todas as portas
resource "aws_security_group_rule" "ingress_k3s_internal" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.k3s_cluster_sg.id
  description       = "Comunicacao interna K3s (node-to-node, pod-to-pod)"
}

# Regra: Egress (Tudo liberado)
resource "aws_security_group_rule" "egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k3s_cluster_sg.id
  description       = "Permitir toda saida"
}

# --- KEY PAIR ---

resource "aws_key_pair" "budget_key" {
  key_name   = "${var.project_name}-budget-key-v12"
  public_key = var.ssh_public_key
}

# --- ELASTIC IPs ---

# EIP para Master
resource "aws_eip" "k3s_master_eip" {
  domain = "vpc"
  tags = { Name = "${var.project_name}-k3s-master-eip" }
}

# --- EC2 INSTANCE: K3S MASTER (m7i-flex.large - SPOT INSTANCE) ---
# 💰 Economia: 85-90% vs On-Demand
# Spot Price: ~$0.036-0.041/hora (~$26-30/mês)
# On-Demand Price: ~$0.150/hora (~$108/mês)

resource "aws_instance" "k3s_master" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = "m7i-flex.large"  # Upgraded from t3.small para melhor performance
  key_name             = aws_key_pair.budget_key.key_name
  subnet_id            = data.terraform_remote_state.network.outputs.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.k3s_cluster_sg.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  # 💰 SPOT INSTANCE CONFIGURATION (economia 85-90%)
  instance_market_options {
    market_type = "spot"
    spot_options {
      # Preço máximo: 53% do on-demand ($0.080 vs $0.150)
      max_price                      = "0.080"
      # Tipo: persistent (mantém até terminado manualmente)
      spot_instance_type             = "persistent"
      # Comportamento: STOP (para em vez de terminar)
      # ✅ EBS e estado do K3s persistem
      # ✅ EIP permanece associado
      instance_interruption_behavior = "stop"
    }
  }

  root_block_device {
    volume_size = 30
    volume_type = "gp2"
  }

  user_data = base64encode(templatefile("${path.module}/scripts/user_data_master.sh.tpl", {
    github_repo     = var.github_repo,
    github_token    = var.github_token,
    aws_region      = var.aws_region,
    db_host         = data.terraform_remote_state.database.outputs.db_instance_address,
    db_name         = data.terraform_remote_state.database.outputs.db_instance_name,
    db_username     = data.terraform_remote_state.database.outputs.db_instance_username,
    db_password     = var.db_password,
    public_ip       = aws_eip.k3s_master_eip.public_ip,
    scripts_version = var.scripts_version
  }))

  tags = {
    Name = "${var.project_name}-k3s-master-spot"
    Role = "master"
    Type = "spot"
    CostOptimized = "true"
  }
}

resource "aws_eip_association" "master_eip_assoc" {
  instance_id   = aws_instance.k3s_master.id
  allocation_id = aws_eip.k3s_master_eip.id
}

# --- EC2 INSTANCE: K3S WORKER - REMOVIDO (otimizacao de custos) ---
# Worker foi terminado para ficar dentro do Free Trial m7i-flex (750h/mes)

# --- NULL RESOURCE: OBTER KUBECONFIG ---

resource "null_resource" "get_kubeconfig" {
  depends_on = [aws_instance.k3s_master]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
      mkdir -p ~/.kube
      echo "📥 Copiando kubeconfig do Master..."

      for i in {1..30}; do
        if scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ${var.ssh_private_key_path} \
            ubuntu@${aws_eip.k3s_master_eip.public_ip}:/home/ubuntu/.kube/config ~/.kube/config; then
          echo "✅ Kubeconfig copiado na tentativa $i!"

          # Substituir 127.0.0.1 pelo IP Público do Master
          sed -i 's/127.0.0.1/${aws_eip.k3s_master_eip.public_ip}/g' ~/.kube/config

          echo "🔍 Verificando nodes do cluster..."
          kubectl get nodes

          break
        fi
        echo "Tentativa $i falhou. Aguardando 10s..."
        sleep 10
      done
    EOT
  }

  triggers = {
    always_run = "${timestamp()}"
  }
}
