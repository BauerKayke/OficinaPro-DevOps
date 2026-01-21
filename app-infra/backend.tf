terraform {
  backend "s3" {
    bucket         = "fiap-oficinapro-ckm-tfstate"
    key            = "oficinapro/app-infra/terraform.tfstate" # <-- Chave específica para a infra da app
    region         = "us-east-1"
    dynamodb_table = "oficinapro-tfstate-lock-table"
    encrypt        = true
  }
}
