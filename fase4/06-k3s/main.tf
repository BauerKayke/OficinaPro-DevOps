# K3s Cluster - Fase 4 (versão mais leve de Kubernetes em EC2)
# 2x t3.micro: 1 server + 1 agent
# K3s: ~50MB binary, SQLite, sem etcd separado - ideal para Free Tier

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  backend "s3" {
    bucket         = "fiap-oficinapro-ckm-tfstate"
    key            = "fase4/k3s/terraform.tfstate"
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
      Phase       = "Fase4-K3s"
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

data "terraform_remote_state" "messaging" {
  backend = "s3"
  config = {
    bucket = "fiap-oficinapro-ckm-tfstate"
    key    = "fase4-optimized/messaging/terraform.tfstate"
    region = "us-east-1"
  }
}

# Token para agentes se juntarem ao cluster
resource "random_password" "k3s_token" {
  length  = 32
  special = false
}

# Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group K3s (sufixo -cluster para não conflitar com 04-compute)
resource "aws_security_group" "k3s" {
  name        = "${var.project_name}-k3s-cluster-sg-fase4"
  description = "K3s cluster 06 - API, SSH, NodePort"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "K3s API (kubectl deploy)"
  }
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
    description = "Inter-node"
  }
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "NodePort"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-k3s-cluster-sg-fase4" }
}

# IAM Role K3s (sufixo -cluster para não conflitar com 04-compute)
resource "aws_iam_role" "k3s" {
  name = "${var.project_name}-k3s-cluster-role-fase4"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "k3s_ssm" {
  role       = aws_iam_role.k3s.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "k3s_sqs" {
  role       = aws_iam_role.k3s.name
  policy_arn = data.terraform_remote_state.messaging.outputs.sqs_access_policy_arn
}

resource "aws_iam_role_policy" "k3s_ssm_param" {
  name = "${var.project_name}-k3s-cluster-ssm-param"
  role = aws_iam_role.k3s.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:PutParameter", "ssm:GetParameter"]
      Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/oficinapro/k3s/*"
    }]
  })
}

resource "aws_iam_instance_profile" "k3s" {
  name = "${var.project_name}-k3s-cluster-profile-fase4"
  role = aws_iam_role.k3s.name
}

# User data K3s Server
locals {
  server_user_data = templatefile("${path.module}/user_data_server.sh", {
    k3s_token = random_password.k3s_token.result
    hostname  = "${var.project_name}-k3s-server-fase4"
  })
}

# K3s Server
resource "aws_instance" "k3s_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type           = var.instance_type
  subnet_id               = data.terraform_remote_state.network.outputs.public_subnet_ids[0]
  vpc_security_group_ids  = [aws_security_group.k3s.id]
  iam_instance_profile    = aws_iam_instance_profile.k3s.name
  user_data               = base64encode(local.server_user_data)
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-k3s-server-fase4"
    Role = "master"
  }
}

# Elastic IP para o server (agent precisa do IP fixo para join)
resource "aws_eip" "k3s_server" {
  domain   = "vpc"
  instance = aws_instance.k3s_server.id
  tags     = { Name = "${var.project_name}-k3s-server-eip-fase4" }
}

# User data K3s Agent
locals {
  agent_user_data = templatefile("${path.module}/user_data_agent.sh", {
    server_url = "https://${aws_eip.k3s_server.public_ip}:6443"
    k3s_token  = random_password.k3s_token.result
    hostname   = "${var.project_name}-k3s-agent-fase4"
  })
}

# K3s Agent
resource "aws_instance" "k3s_agent" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type           = var.instance_type
  subnet_id               = data.terraform_remote_state.network.outputs.public_subnet_ids[1]
  vpc_security_group_ids  = [aws_security_group.k3s.id]
  iam_instance_profile    = aws_iam_instance_profile.k3s.name
  user_data               = base64encode(local.agent_user_data)
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-k3s-agent-fase4"
    Role = "agent"
  }

  depends_on = [aws_eip.k3s_server]
}

# SSM Parameters para pipelines
resource "aws_ssm_parameter" "master_ip" {
  name  = "/oficinapro/k3s/master-ip"
  type  = "String"
  value = aws_eip.k3s_server.public_ip
  tags  = { Phase = "Fase4-K3s" }
}
