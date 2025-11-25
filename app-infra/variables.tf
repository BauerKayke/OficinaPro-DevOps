# Variáveis para a infraestrutura da aplicação

variable "aws_region" {
  description = "Região da AWS"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nome do projeto"
  type        = string
  default     = "fiap-oficinapro-kb"
}

variable "instance_type" {
  description = "Tipo da instância EC2 (otimizado para Free Tier)"
  type        = string
  default     = "t3.micro"
}

variable "spot_max_price" {
  description = "Preço máximo para a Spot Instance (otimizado para Free Tier)"
  type        = string
  default     = "0.007" # Preço baixo para t3.micro
}

variable "ssh_public_key" {
  description = "Chave SSH pública para acesso à instância EC2"
  type        = string
}

variable "github_repo" {
  description = "URL do repositório GitHub da aplicação"
  type        = string
}

variable "github_token" {
  description = "Token do GitHub (PAT) para clonar o repositório"
  type        = string
  sensitive   = true
}

variable "scripts_version" {
  description = "Versão dos scripts de bootstrap para forçar atualização do user_data"
  type        = string
  default     = "v1.0.0"
}
