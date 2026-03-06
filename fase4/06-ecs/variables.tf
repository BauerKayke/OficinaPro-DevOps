variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "oficinapro"
}

variable "environment" {
  description = "Environment"
  type        = string
  default     = "production"
}

variable "cluster_name" {
  description = "ECS cluster name"
  type        = string
  default     = "oficinapro-fase4"
}

variable "instance_type" {
  description = "EC2 instance type for ECS container instances"
  type        = string
  default     = "t3.micro"
}

variable "desired_capacity" {
  description = "Number of EC2 instances (2 = divide carga, Free Tier 750h = 375h cada)"
  type        = number
  default     = 2
}
