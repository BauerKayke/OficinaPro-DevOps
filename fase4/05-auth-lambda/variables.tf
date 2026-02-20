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

variable "lambda_zip_path" {
  description = "Path to Lambda deployment package"
  type        = string
  default     = "/Users/kbmarins/Desktop/Personal/FIAP/auth-oficinapro/bootstrap.zip"
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

variable "jwt_secret" {
  description = "JWT secret key"
  type        = string
  sensitive   = true
}

variable "new_relic_license_key" {
  description = "New Relic license key"
  type        = string
  sensitive   = true
  default     = ""
}
