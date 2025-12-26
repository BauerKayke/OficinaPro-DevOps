terraform {
  backend "s3" {
    bucket         = "oficinapro-tfstate-bucket-unique-name"
    key            = "oficinapro/auth-infra/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "oficinapro-tfstate-lock-table"
    encrypt        = true
  }
}

