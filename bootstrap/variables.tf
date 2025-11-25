# Variáveis para o módulo de bootstrap do backend Terraform

variable "aws_region" {
  description = "Região da AWS para criar o bucket S3 e a tabela DynamoDB."
  type        = string
  default     = "us-east-1"
}

variable "s3_bucket_name" {
  description = "Nome único global para o bucket S3 que armazenará o estado do Terraform."
  type        = string
  default     = "oficinapro-tfstate-bucket-unique-name" # IMPORTANTE: Troque por um nome único!
}

variable "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB para o bloqueio de estado do Terraform."
  type        = string
  default     = "oficinapro-tfstate-lock-table"
}
