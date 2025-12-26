terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.11.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23.0"
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

# --- RECURSOS DA APLICAÇÃO ---

# Security Group para K3s
resource "aws_security_group" "k3s_sg" {
  name        = "${var.project_name}-k3s-sg"
  description = "Security group para o cluster K3s"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id # VEM DA REDE

  # Ingress (entradas)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }
  ingress {
    from_port   = 6443 # K3s API
    to_port     = 6443
    protocol    = "tcp"
    # IMPORTANTE: Liberar acesso externo à API do K3s para o Terraform/Helm poder conectar
    # Em produção, restrinja ao IP do runner ou use bastion
    cidr_blocks = ["0.0.0.0/0"] 
    description = "K3s API server externo"
  }
  
  # Egress (saídas) - permite toda a comunicação de saída
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-k3s-sg" }
}

# Key Pair - Atualizado para v4 para forçar recriação com TLS SAN
resource "aws_key_pair" "budget_key" {
  key_name   = "${var.project_name}-budget-key-v4"
  public_key = var.ssh_public_key
}

# EC2 Instance
resource "aws_instance" "k3s_node" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.budget_key.key_name
  # Pega a primeira subnet pública da rede
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
    db_host         = data.terraform_remote_state.database.outputs.db_instance_address, # VEM DO BANCO
    db_name         = data.terraform_remote_state.database.outputs.db_instance_name,
    db_username     = data.terraform_remote_state.database.outputs.db_instance_username,
    db_password     = var.db_password, # Agora passamos a variável local, mais seguro que ler output sensitive se possível
    instance_type   = var.instance_type,
    eip_allocation_id = aws_eip.k3s_eip.id,
    scripts_version = var.scripts_version
  }))

  tags = { Name = "${var.project_name}-k3s-node" }
}

# Elastic IP
resource "aws_eip" "k3s_eip" {
  domain = "vpc"
  tags = { Name = "${var.project_name}-k3s-eip" }
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.k3s_node.id
  allocation_id = aws_eip.k3s_eip.id
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  insecure       = true # Necessário pois o IP no cert do K3s pode não bater com o IP público
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
    insecure    = true # Necessário pois o IP no cert do K3s pode não bater com o IP público
  }
}

resource "null_resource" "get_kubeconfig" {
  depends_on = [aws_instance.k3s_node]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"] # Força o uso do bash para suportar {1..50}
    command = <<EOT
      mkdir -p ~/.kube
      echo "Aguardando user_data finalizar e criar kubeconfig..."
      for i in {1..50}; do
        if scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i ${var.ssh_private_key_path} ubuntu@${aws_eip.k3s_eip.public_ip}:/home/ubuntu/.kube/config ~/.kube/config; then
          echo "Kubeconfig copiado com sucesso na tentativa $i!"
          
          # Substituir 127.0.0.1 pelo IP Público da instância
          sed -i 's/127.0.0.1/${aws_eip.k3s_eip.public_ip}/g' ~/.kube/config
          
          exit 0
        fi
        echo "Tentativa $i falhou. Aguardando 10s..."
        sleep 10
      done
      echo "timeout: Falha ao copiar kubeconfig após 50 tentativas (500s)."
      exit 1
    EOT
  }

  triggers = {
    # Forçar execução a cada apply para garantir que o arquivo exista no runner
    always_run = "${timestamp()}"
  }
}

resource "helm_release" "newrelic_k8s" {
  depends_on = [null_resource.get_kubeconfig]

  name       = "newrelic-bundle"
  repository = "https://helm-charts.newrelic.com"
  chart      = "nri-bundle"
  namespace  = "newrelic"
  create_namespace = true
  version    = "5.0.25"
  timeout    = 600

  set {
    name  = "global.licenseKey"
    value = var.newrelic_license_key
  }
  set {
    name  = "global.cluster"
    value = "${var.project_name}-cluster"
  }
  set {
    name  = "newrelic-infrastructure.enabled"
    value = "true"
  }
  set {
    name  = "kube-state-metrics.enabled"
    value = "true"
  }
  set {
    name  = "opentelemetry.enabled"
    value = "true"
  }
}
