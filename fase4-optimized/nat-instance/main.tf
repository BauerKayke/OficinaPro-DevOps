# NAT Instance (Cost Optimized) - Replace NAT Gateway
# Saves ~$32/month

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
    key            = "fase4-optimized/nat-instance/terraform.tfstate"
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
      Phase       = "Fase4-Optimized"
    }
  }
}

# Fetch existing VPC by tag
data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["oficinapro-vpc-fase4"]
  }
}

# Fetch public subnets
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  
  filter {
    name   = "tag:Name"
    values = ["oficinapro-public-subnet-*-fase4"]
  }
}

# Fetch private subnets
data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  
  filter {
    name   = "tag:Name"
    values = ["oficinapro-private-subnet-*-fase4"]
  }
}

# Fetch private route table
data "aws_route_table" "private" {
  vpc_id = data.aws_vpc.main.id
  
  filter {
    name   = "tag:Name"
    values = ["oficinapro-private-rt-fase4"]
  }
}

# Latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group for NAT Instance
resource "aws_security_group" "nat_instance" {
  name        = "${var.project_name}-nat-instance-sg-optimized"
  description = "Security group for NAT instance"
  vpc_id      = data.aws_vpc.main.id

  # Allow traffic from private subnets
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.main.cidr_block]
    description = "All traffic from VPC"
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-nat-instance-sg-optimized"
  }
}

# IAM Role for NAT Instance
resource "aws_iam_role" "nat_instance" {
  name = "${var.project_name}-nat-instance-role-optimized"

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
    Name = "${var.project_name}-nat-instance-role"
  }
}

# IAM Instance Profile
resource "aws_iam_instance_profile" "nat_instance" {
  name = "${var.project_name}-nat-instance-profile-optimized"
  role = aws_iam_role.nat_instance.name

  tags = {
    Name = "${var.project_name}-nat-instance-profile"
  }
}

# NAT Instance (t3.micro - Free Tier eligible)
resource "aws_instance" "nat" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"  # Free Tier eligible (750 hours/month free for 12 months)
  
  subnet_id              = tolist(data.aws_subnets.public.ids)[0]
  vpc_security_group_ids = [aws_security_group.nat_instance.id]
  iam_instance_profile   = aws_iam_instance_profile.nat_instance.name
  
  # Disable source/destination check (required for NAT)
  source_dest_check = false

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e
    
    # Enable IP forwarding
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -p
    
    # Configure iptables for NAT
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    iptables -A FORWARD -i eth0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i eth0 -o eth0 -j ACCEPT
    
    # Persist iptables rules
    yum install -y iptables-services
    service iptables save
    systemctl enable iptables
    
    echo "✅ NAT Instance configured successfully!"
  EOF
  )

  tags = {
    Name = "${var.project_name}-nat-instance-optimized"
    Role = "nat"
  }
}

# Elastic IP for NAT Instance
resource "aws_eip" "nat" {
  domain   = "vpc"
  instance = aws_instance.nat.id

  tags = {
    Name = "${var.project_name}-nat-instance-eip-optimized"
  }

  depends_on = [aws_instance.nat]
}

# Update route tables to use NAT Instance instead of NAT Gateway
resource "aws_route" "private_nat" {
  route_table_id         = data.aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}
