variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "oficinapro"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "oficinapro_admin"
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}
