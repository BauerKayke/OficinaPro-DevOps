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

# Data Sources
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "fiap-oficinapro-ckm-tfstate"
    key    = "oficinapro/network/terraform.tfstate"
    region = "us-east-1"
  }
}

data "aws_vpc" "main" {
  id = data.terraform_remote_state.network.outputs.vpc_id
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.terraform_remote_state.network.outputs.vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = ["*public*"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.terraform_remote_state.network.outputs.vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = ["*private*"]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# IAM Role para EC2 (SSM Access)
resource "aws_iam_role" "ec2_role" {
  name = "oficinapro_ec2_role_hybrid"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Política adicional para ler/escrever parâmetros SSM (token do K3s)
resource "aws_iam_policy" "ssm_parameters" {
  name        = "oficinapro_ssm_parameters_policy"
  description = "Permite ler e escrever parametros do K3s no SSM"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:PutParameter",
          "ssm:GetParameter",
          "ssm:DeleteParameter"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/oficinapro/k3s/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_parameters_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ssm_parameters.arn
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "oficinapro_ec2_profile_hybrid"
  role = aws_iam_role.ec2_role.name
}

# Security Group para os Nodes (Master e Worker)
resource "aws_security_group" "k3s_sg" {
  name        = "oficinapro-k3s-sg-hybrid"
  description = "Security Group para Cluster K3s (Master e Worker)"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Idealmente restringir ao seu IP ou Bastion
  }

  # HTTP/HTTPS (Ingress)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # K3s API (Interno e Externo para kubectl)
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Comunicação Interna Total (Master <-> Worker)
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Egress Total
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "oficinapro-k3s-sg"
  }
}

# --- MASTER NODE (t3.small) ---
resource "aws_instance" "k3s_master" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.small" # 2GB RAM, 2 vCPU
  subnet_id     = data.aws_subnets.public.ids[0] # Publica para acesso SSH facilitado (ou privada com NAT)
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.k3s_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  user_data = templatefile("${path.module}/scripts/user_data_master.sh.tpl", {})

  tags = {
    Name = "oficinapro-k3s-master"
    Role = "master"
  }
}

# Elastic IP para o Master (para manter o endpoint da API fixo)
resource "aws_eip" "master_eip" {
  instance = aws_instance.k3s_master.id
  domain   = "vpc"
  tags = {
    Name = "oficinapro-k3s-master-eip"
  }
}

# --- WORKER NODE (t3.medium) ---
resource "aws_instance" "k3s_worker" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium" # 4GB RAM, 2 vCPU
  subnet_id     = data.aws_subnets.public.ids[0] # Mesma subnet por simplicidade de latência
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.k3s_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  # Depende do Master para garantir que o user_data rode depois (embora o script tenha loop de espera)
  depends_on = [aws_instance.k3s_master]

  user_data = templatefile("${path.module}/scripts/user_data_worker.sh.tpl", {})

  tags = {
    Name = "oficinapro-k3s-worker-01"
    Role = "worker"
  }
}

# Elastic IP para o Worker (opcional, mas bom para debug direto se precisar)
resource "aws_eip" "worker_eip" {
  instance = aws_instance.k3s_worker.id
  domain   = "vpc"
  tags = {
    Name = "oficinapro-k3s-worker-eip"
  }
}

# --- LOAD BALANCER (ALB) ---
resource "aws_security_group" "alb_sg" {
  name        = "oficinapro-alb-sg-hybrid"
  description = "Security Group para ALB Interno"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # Apenas VPC
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "app_alb" {
  name               = "fiap-oficinapro-kb-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.private.ids

  enable_deletion_protection = false

  tags = {
    Name = "fiap-oficinapro-alb"
  }
}

resource "aws_lb_target_group" "app_tg" {
  name        = "fiap-oficinapro-tg"
  port        = 30080 # NodePort do Ingress Controller (padrão K3s costuma ser aleatório ou configurável, aqui assumiremos 80 via host network ou NodePort fixo)
  # AJUSTE: K3s com Traefik/Nginx geralmente expõe 80/443 no host se usar HostPort.
  # Se usarmos NodePort, precisamos fixar. Vamos assumir tráfego na porta 80 do host (ingress controller listening on host network)
  protocol    = "HTTP"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id
  target_type = "instance"

  health_check {
    path                = "/api/v1/actuator/health" # Health check da aplicação principal
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 5
    matcher             = "200-499"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# Attach Master Node to ALB
resource "aws_lb_target_group_attachment" "master_attach" {
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.k3s_master.id
  port             = 80
}

# Attach Worker Node to ALB
resource "aws_lb_target_group_attachment" "worker_attach" {
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.k3s_worker.id
  port             = 80
}
