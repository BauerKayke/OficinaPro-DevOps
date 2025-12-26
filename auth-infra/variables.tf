variable "aws_region" {
  description = "Região da AWS"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto (usado para encontrar a VPC e nomear recursos)"
  type        = string
  default     = "fiap-oficinapro-kb"
}

variable "lambda_name" {
  description = "Nome da função Lambda"
  type        = string
  default     = "oficinapro-auth-function"
}

# Caminho para o ZIP da Lambda. 
# No pipeline, este arquivo será gerado pelo build do Go.
variable "lambda_zip_path" {
  description = "Caminho para o arquivo ZIP contendo o binário da Lambda"
  type        = string
  default     = "function.zip" 
}

# Variáveis de Ambiente para a Lambda
variable "db_host" {
  description = "Host do banco de dados (será injetado via secret ou data source)"
  type        = string
  default     = ""
}

variable "db_user" {
  description = "Usuário do banco de dados"
  type        = string
  default     = "oficinapro_user"
}

variable "db_password" {
  description = "Senha do banco de dados"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Nome do banco de dados"
  type        = string
  default     = "oficinapro"
}

variable "jwt_secret" {
  description = "Segredo para assinatura do JWT"
  type        = string
  sensitive   = true
}

