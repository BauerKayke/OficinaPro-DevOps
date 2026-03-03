# Compute Infrastructure - Fase 4
# EC2 K3s + ALB

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
    key            = "fase4/compute/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "oficinapro-tfstate-lock-table"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "OficinaPro"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Phase       = "Fase4"
    }
  }
}

# Remote state from network
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "fiap-oficinapro-ckm-tfstate"
    key    = "fase4/network/terraform.tfstate"
    region = "us-east-1"
  }
}

# Remote state from messaging
data "terraform_remote_state" "messaging" {
  backend = "s3"
  config = {
    bucket = "fiap-oficinapro-ckm-tfstate"
    key    = "fase4-optimized/messaging/terraform.tfstate"
    region = "us-east-1"
  }
}

# Latest Ubuntu AMI
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

# Security Group for K3s
resource "aws_security_group" "k3s" {
  name        = "${var.project_name}-k3s-sg-fase4"
  description = "Security group for K3s cluster"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  # SSH from anywhere (temporarily, should be restricted)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH access"
  }

  # K3s API (VPC + internet para deploy via kubectl do GitHub Runner)
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [data.terraform_remote_state.network.outputs.vpc_cidr]
    description = "K3s API (VPC)"
  }
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "K3s API (deploy via kubectl - GitHub Runner)"
  }

  # HTTP from ALB
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "HTTP from ALB"
  }

  # HTTPS from ALB
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "HTTPS from ALB"
  }

  # NodePort range
  ingress {
    from_port       = 30000
    to_port         = 32767
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "K3s NodePort range"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-k3s-sg-fase4"
  }
}

# Security group for VPC endpoints (SSM)
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-vpc-endpoints-sg-fase4"
  description = "Allow VPC traffic to SSM endpoints"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.terraform_remote_state.network.outputs.vpc_cidr]
    description = "HTTPS from VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-vpc-endpoints-sg-fase4"
  }
}

# VPC Endpoints for SSM - permite que instância use SSM sem internet
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = data.terraform_remote_state.network.outputs.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.terraform_remote_state.network.outputs.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ssm-endpoint-fase4"
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = data.terraform_remote_state.network.outputs.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.terraform_remote_state.network.outputs.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ec2messages-endpoint-fase4"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = data.terraform_remote_state.network.outputs.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.terraform_remote_state.network.outputs.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ssmmessages-endpoint-fase4"
  }
}

# Security Group for ALB
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg-fase4"
  description = "Security group for Application Load Balancer"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from internet"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg-fase4"
  }
}

# IAM Role for EC2 (K3s)
resource "aws_iam_role" "k3s" {
  name = "${var.project_name}-k3s-role-fase4"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-k3s-role"
  }
}

# Attach SSM policy
resource "aws_iam_role_policy_attachment" "k3s_ssm" {
  role       = aws_iam_role.k3s.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach SQS policy
resource "aws_iam_role_policy_attachment" "k3s_sqs" {
  role       = aws_iam_role.k3s.name
  policy_arn = data.terraform_remote_state.messaging.outputs.sqs_access_policy_arn
}

# ECR pull (para imagens Docker nos deploys)
resource "aws_iam_role_policy_attachment" "k3s_ecr" {
  role       = aws_iam_role.k3s.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Policy para gravar kubeconfig no Parameter Store (deploy via kubectl)
resource "aws_iam_role_policy" "k3s_ssm_param" {
  name = "${var.project_name}-k3s-ssm-param"
  role = aws_iam_role.k3s.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:PutParameter", "ssm:GetParameter"]
      Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/oficinapro/k3s/kubeconfig*"
    }]
  })
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "k3s" {
  name = "${var.project_name}-k3s-profile-fase4"
  role = aws_iam_role.k3s.name

  tags = {
    Name = "${var.project_name}-k3s-profile"
  }
}

# EC2 Key Pair
resource "aws_key_pair" "k3s" {
  key_name   = "${var.project_name}-k3s-key-fase4"
  public_key = var.ssh_public_key

  tags = {
    Name = "${var.project_name}-k3s-key"
  }
}

# EC2 Instance for K3s
resource "aws_instance" "k3s" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  
  subnet_id              = data.terraform_remote_state.network.outputs.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.k3s.id]
  iam_instance_profile   = aws_iam_instance_profile.k3s.name
  key_name               = aws_key_pair.k3s.key_name

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    hostname = "${var.project_name}-k3s-fase4"
  }))

  tags = {
    Name = "${var.project_name}-k3s-node-fase4"
    Role = "master"
  }
}

# Elastic IP for K3s
resource "aws_eip" "k3s" {
  domain   = "vpc"
  instance = aws_instance.k3s.id

  tags = {
    Name = "${var.project_name}-k3s-eip-fase4"
  }

  depends_on = [aws_instance.k3s]
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb-fase4"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.terraform_remote_state.network.outputs.public_subnet_ids

  enable_deletion_protection = false
  enable_http2               = true

  tags = {
    Name = "${var.project_name}-alb-fase4"
  }
}

# Target Group
resource "aws_lb_target_group" "k3s" {
  name     = "${var.project_name}-k3s-tg-fase4"
  port     = 30080
  protocol = "HTTP"
  vpc_id   = data.terraform_remote_state.network.outputs.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
  }

  tags = {
    Name = "${var.project_name}-k3s-tg"
  }
}

# Target Group Attachment
resource "aws_lb_target_group_attachment" "k3s" {
  target_group_arn = aws_lb_target_group.k3s.arn
  target_id        = aws_instance.k3s.id
  port             = 30080
}

# ALB Listener HTTP
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k3s.arn
  }
}
