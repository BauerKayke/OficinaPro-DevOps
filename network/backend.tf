terraform {
  backend "s3" {
    bucket         = "fiap-oficinapro-kb-tfstate"
    key            = "oficinapro/network/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "oficinapro-tfstate-lock-table"
    encrypt        = true
  }
}

