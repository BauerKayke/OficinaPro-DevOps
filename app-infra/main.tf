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

# --- DATA SOURCE: LER O ESTADO DO BANCO DE DADOS ---
data "terraform_remote_state" "database" {
  backend = "s3"
  config = {
    bucket = "oficinapro-tfstate-bucket-unique-name"
    key    = "oficinapro/database/terraform.tfstate"
    region = var.aws_region
  }
}

# Data sources
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

# --- RECURSOS DE REDE E COMPUTAÇÃO ---

# VPC, Subnets, IGW, Route Tables...
resource "aws_vpc" "budget_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "${var.project_name}-budget-vpc" }
}

resource "aws_internet_gateway" "budget_igw" {
  vpc_id = aws_vpc.budget_vpc.id
  tags = { Name = "${var.project_name}-budget-igw" }
}

resource "aws_subnet" "budget_public_subnet_1" {
  vpc_id                  = aws_vpc.budget_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-budget-public-subnet-1" }
}

resource "aws_subnet" "budget_public_subnet_2" {
  vpc_id                  = aws_vpc.budget_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-budget-public-subnet-2" }
}

resource "aws_route_table" "budget_public_rt" {
  vpc_id = aws_vpc.budget_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.budget_igw.id
  }
  tags = { Name = "${var.project_name}-budget-public-rt" }
}

resource "aws_route_table_association" "budget_public_rta_1" {
  subnet_id      = aws_subnet.budget_public_subnet_1.id
  route_table_id = aws_route_table.budget_public_rt.id
}

resource "aws_route_table_association" "budget_public_rta_2" {
  subnet_id      = aws_subnet.budget_public_subnet_2.id
  route_table_id = aws_route_table.budget_public_rt.id
}

# Security Group para K3s
resource "aws_security_group" "k3s_sg" {
  name        = "${var.project_name}-k3s-sg"
  description = "Security group para o cluster K3s"
  vpc_id      = aws_vpc.budget_vpc.id

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
    self        = true
    description = "K3s API server interno"
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

# Key Pair
resource "aws_key_pair" "budget_key" {
  key_name   = "${var.project_name}-budget-key"
  public_key = var.ssh_public_key
}

# EC2 Instance
resource "aws_instance" "k3s_node" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.budget_key.key_name
  subnet_id     = aws_subnet.budget_public_subnet_1.id
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
    db_password     = nonsensitive(data.terraform_remote_state.database.outputs.db_instance_password_secret), # Assumindo que a senha é output de um secret
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
