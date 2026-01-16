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
    bucket = "fiap-oficinapro-kb-tfstate"
    key    = "oficinapro/network/terraform.tfstate"
    region = var.aws_region
  }
}

# Lê o estado do BANCO (Endpoint)
data "terraform_remote_state" "database" {
  backend = "s3"
  config = {
    bucket = "fiap-oficinapro-kb-tfstate"
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

# Security Group do ALB (Permite HTTP/HTTPS de qualquer lugar)
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group para o ALB Publico"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP Publico"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS Publico"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-alb-sg" }
}

# ALB Público
resource "aws_lb" "app_alb" {
  name               = "${var.project_name}-alb"
  internal           = false
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
    path                = "/actuator/health" # Health Check da aplicação (via Nginx)
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }
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

# Associação do EC2 ao Target Group
resource "aws_lb_target_group_attachment" "ec2_attach" {
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.k3s_node.id
  port             = 80
}

# --- RECURSOS DA INSTÂNCIA EC2 (K3s) ---

# Security Group para K3s (Restrito)
resource "aws_security_group" "k3s_sg" {
  name        = "${var.project_name}-k3s-sg-v5" # v5 para forçar recriação
  description = "Security group para o cluster K3s"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  tags = { Name = "${var.project_name}-k3s-sg-v5" }

  lifecycle {
    create_before_destroy = true
  }
}

# Regra: SSH liberado (necessário para CI/CD via SSH Action)
resource "aws_security_group_rule" "ingress_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"] # Idealmente restringir ao GitHub Actions IP
  security_group_id = aws_security_group.k3s_sg.id
  description       = "SSH para CI/CD"
}

# Regra: API Server (necessário para kubectl remoto se usado)
resource "aws_security_group_rule" "ingress_k3s_api" {
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k3s_sg.id
  description       = "K3s API server externo"
}

# Regra: HTTP (80) APENAS do ALB (Segurança!)
resource "aws_security_group_rule" "ingress_http_from_alb" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id # Apenas tráfego do ALB
  security_group_id        = aws_security_group.k3s_sg.id
  description              = "HTTP apenas via ALB"
}

# Regra: HTTPS (443) APENAS do ALB
resource "aws_security_group_rule" "ingress_https_from_alb" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg.id
  security_group_id        = aws_security_group.k3s_sg.id
  description              = "HTTPS apenas via ALB"
}

# Regra: Interna (Node-to-Node)
resource "aws_security_group_rule" "ingress_k3s_internal" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.k3s_sg.id
  description       = "Comunicacao interna entre nodes/pods"
}

# Regra: Egress (Tudo liberado)
resource "aws_security_group_rule" "egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.k3s_sg.id
  description       = "Permitir toda saida"
}

# Key Pair
resource "aws_key_pair" "budget_key" {
  key_name   = "${var.project_name}-budget-key-v11" # v11
  public_key = var.ssh_public_key
}

# Elastic IP (Necessário para manter IP fixo para SSH e DNS se não usarmos ALB, mas aqui mantemos para SSH)
resource "aws_eip" "k3s_eip" {
  domain = "vpc"
  tags = { Name = "${var.project_name}-k3s-eip" }
}

# EC2 Instance (Subnet Pública para permitir SSH direto)
resource "aws_instance" "k3s_node" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.budget_key.key_name
  subnet_id     = data.terraform_remote_state.network.outputs.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.k3s_sg.id]

  root_block_device {
    volume_size = 30
    volume_type = "gp2"
  }

  user_data = base64encode(templatefile("${path.module}/scripts/user_data.sh.tpl", {
    github_repo     = var.github_repo,
    github_token    = var.github_token,
    aws_region      = var.aws_region,
    db_host         = data.terraform_remote_state.database.outputs.db_instance_address,
    db_name         = data.terraform_remote_state.database.outputs.db_instance_name,
    db_username     = data.terraform_remote_state.database.outputs.db_instance_username,
    db_password     = var.db_password,
    instance_type   = var.instance_type,
    public_ip       = aws_eip.k3s_eip.public_ip, # IP Injetado diretamente
    scripts_version = var.scripts_version
  }))

  tags = { Name = "${var.project_name}-k3s-node" }
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.k3s_node.id
  allocation_id = aws_eip.k3s_eip.id
}

resource "null_resource" "get_kubeconfig" {
  depends_on = [aws_instance.k3s_node, aws_eip_association.eip_assoc]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<EOT
      mkdir -p ~/.kube
      echo "Aguardando user_data finalizar e criar kubeconfig..."

      # 1. Copiar o arquivo kubeconfig
      for i in {1..60}; do
        if scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ${var.ssh_private_key_path} ubuntu@${aws_eip.k3s_eip.public_ip}:/home/ubuntu/.kube/config ~/.kube/config; then
          echo "Kubeconfig copiado com sucesso na tentativa $i!"
          # Substituir 127.0.0.1 pelo IP Público da instância
          sed -i 's/127.0.0.1/${aws_eip.k3s_eip.public_ip}/g' ~/.kube/config
          break
        fi
        echo "Tentativa SCP $i falhou. Aguardando 10s..."
        sleep 10
      done

      if [ ! -f ~/.kube/config ]; then
        echo "timeout: Falha ao copiar kubeconfig após 60 tentativas."
        exit 1
      fi

      # 2. Verificar conectividade com a porta da API (6443) antes de prosseguir
      echo "Verificando conectividade com K3s API em ${aws_eip.k3s_eip.public_ip}:6443..."
      for i in {1..30}; do
        if timeout 5 bash -c "cat < /dev/null > /dev/tcp/${aws_eip.k3s_eip.public_ip}/6443"; then
          echo "Porta 6443 acessível!"
          exit 0
        fi
        echo "Porta 6443 inacessível (tentativa $i/30). Aguardando 10s..."
        sleep 10
      done

      echo "timeout: Falha ao conectar na porta 6443 do K3s."
      exit 1
    EOT
  }

  triggers = {
    always_run = "${timestamp()}"
  }
}
