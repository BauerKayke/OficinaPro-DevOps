# OficinaPro - Infraestrutura e DevOps

Este repositório centraliza o código de infraestrutura (IaC com Terraform) e os pipelines de CI/CD para o projeto OficinaPro.

## Estrutura do Repositório

- **`bootstrap/`**: Infraestrutura inicial. Cria o bucket S3 e a tabela DynamoDB usados como backend remoto para o estado do Terraform.
- **`app-infra/`**: Infraestrutura da aplicação principal. Gerencia VPC, Subnets, EC2, instalação do Kubernetes (K3s) e monitoramento com New Relic.
- **`auth-infra/`**: Infraestrutura de autenticação. Gerencia a função Serverless (AWS Lambda) e o API Gateway.

## Pipelines (GitHub Actions)

Os workflows estão configurados para serem executados manualmente (`workflow_dispatch`) para maior controle.

1.  **Bootstrap Infra Backend**: Cria o bucket S3. Execute este primeiro (uma única vez).
2.  **App Infra CI/CD**: Cria/Destrói a infraestrutura da aplicação (VPC, K8s).
3.  **Auth Infra CI/CD**: Cria/Destrói a infraestrutura de autenticação (Lambda, API Gateway).

