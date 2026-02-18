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

resource "aws_lb_target_group_attachment" "worker_attach" {
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.k3s_worker.id
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

# EIP para Worker
resource "aws_eip" "k3s_worker_eip" {
  domain = "vpc"
  tags = { Name = "${var.project_name}-k3s-worker-eip" }
}

# --- EC2 INSTANCE: K3S MASTER (t3.small - Control Plane Only) ---

resource "aws_instance" "k3s_master" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = "t3.small"  # Leve: apenas control plane + 1 serviço Go
  key_name             = aws_key_pair.budget_key.key_name
  subnet_id            = data.terraform_remote_state.network.outputs.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.k3s_cluster_sg.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

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
    Name = "${var.project_name}-k3s-master"
    Role = "master"
  }
}

resource "aws_eip_association" "master_eip_assoc" {
  instance_id   = aws_instance.k3s_master.id
  allocation_id = aws_eip.k3s_master_eip.id
}

# --- EC2 INSTANCE: K3S WORKER (t3.medium - All Workloads) ---

resource "aws_instance" "k3s_worker" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = "m7i-flex.large"  # 8GB RAM: Ideal para todos os 7 serviços!
  key_name             = aws_key_pair.budget_key.key_name
  subnet_id            = data.terraform_remote_state.network.outputs.public_subnet_ids[1]
  vpc_security_group_ids = [aws_security_group.k3s_cluster_sg.id]
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size = 30
    volume_type = "gp2"
  }

  user_data = base64encode(templatefile("${path.module}/scripts/user_data_worker.sh.tpl", {
    master_private_ip = aws_instance.k3s_master.private_ip,
    aws_region        = var.aws_region,
    public_ip         = aws_eip.k3s_worker_eip.public_ip,
    scripts_version   = var.scripts_version
  }))

  tags = {
    Name = "${var.project_name}-k3s-worker"
    Role = "worker"
  }

  depends_on = [aws_instance.k3s_master]
}

resource "aws_eip_association" "worker_eip_assoc" {
  instance_id   = aws_instance.k3s_worker.id
  allocation_id = aws_eip.k3s_worker_eip.id
}

# --- NULL RESOURCE: COPIAR TOKEN DO MASTER E CONFIGURAR WORKER ---

resource "null_resource" "configure_worker" {
  depends_on = [
    aws_instance.k3s_master,
    aws_instance.k3s_worker,
    aws_eip_association.master_eip_assoc,
    aws_eip_association.worker_eip_assoc
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
      echo "⏳ Aguardando K3s Master estar pronto (120s)..."
      sleep 120

      echo "📥 Obtendo token do K3s Master..."
      K3S_TOKEN=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 -i ${var.ssh_private_key_path} ubuntu@${aws_eip.k3s_master_eip.public_ip} \
        'sudo cat /var/lib/rancher/k3s/server/node-token' 2>/dev/null)

      if [ -z "$K3S_TOKEN" ]; then
        echo "❌ Erro: Não foi possível obter o token do Master"
        exit 1
      fi

      echo "✅ Token obtido: $${K3S_TOKEN:0:20}..."

      echo "🔗 Configurando Worker para conectar ao Master..."
      ssh -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} ubuntu@${aws_eip.k3s_worker_eip.public_ip} << 'WORKER_EOF'
        # Aguardar cloud-init finalizar
        cloud-init status --wait || true

        # Instalar K3s agent
        echo "📦 Instalando K3s agent..."
        curl -sfL https://get.k3s.io | K3S_URL=https://${aws_instance.k3s_master.private_ip}:6443 \
          K3S_TOKEN="$K3S_TOKEN" \
          INSTALL_K3S_EXEC="agent" \
          sh -

        echo "✅ K3s agent instalado"
WORKER_EOF

      echo "✅ Worker configurado com sucesso!"
    EOT
  }

  triggers = {
    always_run = "${timestamp()}"
  }
}

# --- NULL RESOURCE: OBTER KUBECONFIG ---

resource "null_resource" "get_kubeconfig" {
  depends_on = [null_resource.configure_worker]

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
