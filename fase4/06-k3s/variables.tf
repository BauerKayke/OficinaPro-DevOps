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
  description = "EC2 instance type (t3.micro Free Tier)"
  type        = string
  default     = "t3.micro"
}
