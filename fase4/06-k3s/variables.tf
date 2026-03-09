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

variable "instance_type" {
  description = "EC2 instance type do agent (t3.micro Free Tier)"
  type        = string
  default     = "t3.micro"
}

variable "server_instance_type" {
  description = "EC2 instance type do server (t3.small recomendado - API responde TLS melhor)"
  type        = string
  default     = "t3.small"
}
