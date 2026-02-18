# 🏗️ OficinaPro - Infraestrutura e DevOps

[![Terraform](https://img.shields.io/badge/Terraform-1.5+-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Cloud-FF9900?logo=amazon-aws)](https://aws.amazon.com/)
[![K3s](https://img.shields.io/badge/K3s-1.28+-326CE5?logo=kubernetes)](https://k3s.io/)
[![License](https://img.shields.io/badge/License-Academic-blue)](LICENSE)

## 📋 Descrição

Este repositório centraliza toda a **Infrastructure as Code (IaC)** do projeto OficinaPro, utilizando Terraform para provisionar e gerenciar recursos na AWS. A infraestrutura suporta uma arquitetura de microserviços com autenticação serverless e aplicações containerizadas em K3s.

**Fase Atual:** Fase 4 - Produção em K3s AWS com observabilidade completa

## 🎯 Propósito

- Provisionar infraestrutura completa na AWS de forma automatizada
- Garantir reprodutibilidade e versionamento da infraestrutura
- Separar responsabilidades em módulos independentes
- Facilitar o deploy através de pipelines CI/CD
- Observabilidade e monitoramento completos

## 🛠️ Tecnologias e Serviços

| Tecnologia | Versão | Descrição |
|------------|--------|-----------|
| **Terraform** | >= 1.5 | Infrastructure as Code |
| **AWS Provider** | ~> 5.0 | Provider para recursos AWS |
| **K3s** | 1.28+ | Kubernetes leve para edge/prod |
| **GitHub Actions** | - | CI/CD Pipelines |
| **Docker** | - | Containerização |
| **OpenTelemetry** | 1.22+ | Observabilidade padronizada |
| **New Relic** | - | APM e Monitoring |

### Serviços AWS Provisionados

| Serviço | Uso | Custo/mês |
|---------|-----|-----------|
| **VPC** | Rede virtual isolada (10.1.0.0/16) | Grátis |
| **Subnets** | Públicas e privadas (multi-AZ) | Grátis |
| **Internet Gateway** | Conectividade pública | Grátis |
| **EC2 (Master)** | K3s control plane (t3.small) | ~$15 |
| **EC2 (Worker)** | K3s workloads (t3.small) | ~$15 |
| **EIP** | IPs públicos fixos (2x) | ~$7 |
| **ALB** | Load Balancer para apps | ~$18 |
| **RDS PostgreSQL** | Database consolidado (db.t3.micro) | ~$15 |
| **Lambda** | Funções serverless (Auth, Order) | <$5 |
| **API Gateway** | Gateway HTTP para Lambdas | <$5 |
| **ECR** | Container registry | <$1 |
| **CloudWatch** | Logs e métricas | ~$5 |
| **TOTAL** | - | **~$85/mês** |

## 📁 Estrutura do Repositório

```
OficinaPro-DevOps/
├── bootstrap/              # Backend remoto (S3 + DynamoDB) - executar primeiro!
│   ├── main.tf
│   ├── backend.tf
│   └── variables.tf
├── network/                # VPC, Subnets, IGW (10.1.0.0/16)
│   ├── main.tf
│   ├── backend.tf
│   ├── outputs.tf
│   └── variables.tf
├── auth-infra/             # Lambda + API Gateway (Auth e Order)
│   ├── main.tf
│   ├── backend.tf
│   └── variables.tf
├── app-infra/              # EC2, ALB, K3s (Master + Worker)
│   ├── main.tf
│   ├── backend.tf
│   ├── outputs.tf
│   ├── variables.tf
│   └── scripts/
│       └── user_data.sh.tpl
└── .github/
    └── workflows/          # Pipelines CI/CD
        ├── bootstrap-infra.yml
        ├── network-infra.yml
        ├── auth-infra.yml
        └── app-infra.yml
```

## 🏗️ Arquitetura da Infraestrutura (Fase 4)

### Cluster K3s em Produção

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              AWS us-east-1                                    │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                       VPC (10.1.0.0/16)                                 │  │
│  │                                                                         │  │
│  │  ┌────────────────────────┐        ┌────────────────────────┐          │  │
│  │  │  Public Subnet (AZ-A)  │        │  Public Subnet (AZ-B)  │          │  │
│  │  │    (10.1.0.0/24)       │        │    (10.1.1.0/24)       │          │  │
│  │  │                        │        │                        │          │  │
│  │  │  ┌──────────────────┐  │        │  ┌──────────────────┐  │          │  │
│  │  │  │ K3s Master Node  │  │        │  │ K3s Worker Node  │  │          │  │
│  │  │  │ ───────────────  │  │        │  │ ───────────────  │  │          │  │
│  │  │  │ t3.small (2GB)   │  │        │  │ t3.small (2GB)   │  │          │  │
│  │  │  │ 44.214.64.63     │  │        │  │ 34.228.205.101   │  │          │  │
│  │  │  │ Control Plane    │◀─┼────────┼──│ Workloads        │  │          │  │
│  │  │  └──────────────────┘  │        │  └──────────────────┘  │          │  │
│  │  │           │            │        │           │            │          │  │
│  │  │           ▼            │        │           ▼            │          │  │
│  │  │    ┌─────────────┐    │        │    ┌─────────────┐    │          │  │
│  │  │    │  ALB Target │    │        │    │  ALB Target │    │          │  │
│  │  │    │   Group     │    │        │    │   Group     │    │          │  │
│  │  │    └─────────────┘    │        │    └─────────────┘    │          │  │
│  │  └────────────────────────┘        └────────────────────────┘          │  │
│  │                                                                         │  │
│  │  ┌────────────────────────────────────────────────────────────────┐    │  │
│  │  │                Private Subnet (10.1.10.0/24)                   │    │  │
│  │  │                                                                 │    │  │
│  │  │  ┌──────────────────────────────────────────────────────────┐  │    │  │
│  │  │  │  RDS PostgreSQL (Multi-AZ)                               │  │    │  │
│  │  │  │  ──────────────────────────────                          │  │    │  │
│  │  │  │  oficinapro-consolidated-db.cmz0ic48gh2u.us-east-1...    │  │    │  │
│  │  │  │  db.t3.micro                                             │  │    │  │
│  │  │  │  Database: os_db                                         │  │    │  │
│  │  │  │  User: oficinapro_admin                                  │  │    │  │
│  │  │  └──────────────────────────────────────────────────────────┘  │    │  │
│  │  └────────────────────────────────────────────────────────────────┘    │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌────────────────────────────────────────────────────────────────────────┐  │
│  │                      SERVERLESS (Lambda + API GW)                       │  │
│  │  ┌──────────────────┐              ┌──────────────────┐                │  │
│  │  │  Auth Service    │              │  Order Service   │                │  │
│  │  │  (Go Function)   │              │  (Go Function)   │                │  │
│  │  └──────────────────┘              └──────────────────┘                │  │
│  └────────────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Microserviços no K3s:**
1. ✅ **saga-orchestrator** (Java/Spring Boot) - Coordenação de sagas
2. ✅ **billing-service** (Java/Spring Boot) - Faturamento
3. ✅ **customer-service** (Java/Spring Boot) - Gestão de clientes
4. ✅ **execution-service** (Java/Spring Boot) - Execução de ordens
5. ✅ **payment-api** (Python/FastAPI) - Integração Mercado Pago

**Serverless (Lambda):**
6. ✅ **auth-service** (Go) - Autenticação JWT
7. ✅ **order-service** (Go) - Gestão de ordens

## 🚀 Guia de Deploy

### Pré-requisitos

```bash
# Instalar ferramentas
brew install terraform awscli kubectl  # macOS
# ou
sudo apt-get install terraform awscli  # Linux

# Configurar AWS
aws configure
# AWS Access Key ID: <sua-key>
# AWS Secret Access Key: <sua-secret>
# Default region name: us-east-1
```

### Ordem de Execução

#### 1. Bootstrap (executar apenas uma vez)

```bash
cd bootstrap/
terraform init
terraform apply -auto-approve
```

**O que provisiona:**
- Bucket S3: `fiap-oficinapro-ckm-tfstate`
- DynamoDB Table: `oficinapro-tfstate-lock-table`

#### 2. Network (Rede)

```bash
cd ../network/
terraform init
terraform apply -auto-approve
```

**O que provisiona:**
- VPC `10.1.0.0/16`
- 2 Public Subnets (`10.1.0.0/24`, `10.1.1.0/24`)
- 1 Private Subnet (`10.1.10.0/24`)
- Internet Gateway
- Route Tables

#### 3. Database (ver repo OficinaPro-Database)

```bash
cd ../../OficinaPro-Database/
terraform init
terraform apply -auto-approve
```

**O que provisiona:**
- RDS PostgreSQL `os_db`
- Security Groups
- Subnet Groups

#### 4. Auth Infrastructure

```bash
cd ../OficinaPro-DevOps/auth-infra/
terraform init
terraform apply -auto-approve
```

**O que provisiona:**
- Lambda Functions (Auth + Order)
- API Gateway HTTP
- IAM Roles

#### 5. App Infrastructure (K3s)

```bash
cd ../app-infra/
terraform init
terraform apply

# Será solicitado:
# - github_repo: Seu GitHub username
# - github_token: Personal Access Token do GitHub
```

**O que provisiona:**
- 2x EC2 instances (Master + Worker)
- K3s instalado e configurado
- ALB (Application Load Balancer)
- Security Groups
- IAM Instance Profiles
- 2x Elastic IPs

#### 6. Configurar kubectl

```bash
# Copiar kubeconfig do Master
ssh -i ~/.ssh/chave_nova ubuntu@44.214.64.63 "sudo cat /etc/rancher/k3s/k3s.yaml" > k3s-config.yaml

# Atualizar IP
sed -i 's/127.0.0.1/44.214.64.63/g' k3s-config.yaml

# Configurar
export KUBECONFIG=$(pwd)/k3s-config.yaml

# Testar
kubectl get nodes
kubectl get namespaces
```

## 🔄 CI/CD Pipeline

### GitHub Actions Workflows

Todos os workflows estão em `.github/workflows/`:

| Workflow | Trigger | Descrição |
|----------|---------|-----------|
| `bootstrap-infra.yml` | Manual | Provisiona S3 + DynamoDB (executar primeiro) |
| `network-infra.yml` | Manual | Provisiona VPC e redes |
| `auth-infra.yml` | Manual | Provisiona Lambda + API GW |
| `app-infra.yml` | Manual | Provisiona K3s cluster |

### Secrets do GitHub Necessários

Configure em `Settings > Secrets and variables > Actions`:

| Secret | Descrição | Exemplo |
|--------|-----------|---------|
| `AWS_ACCESS_KEY_ID` | Credencial AWS | `AKIA...` |
| `AWS_SECRET_ACCESS_KEY` | Credencial AWS | `wJalr...` |
| `K3S_SSH_PRIVATE_KEY` | Chave SSH para K3s | Conteúdo do arquivo `.pem` |
| `DB_PASSWORD` | Senha do RDS | `K9fQ7T2mLE8ZxPOficinaPro` |
| `NEW_RELIC_LICENSE_KEY` | License do New Relic | `eu01xxf5c...` |
| `MP_TOKEN` | Token Mercado Pago | `TEST-872...` |

### Fluxo de Deploy dos Microserviços

Cada repositório de microserviço tem seu próprio pipeline:

```
┌──────────────────────────────────────────────────────────────────────┐
│                         GITHUB ACTIONS FLOW                           │
│                                                                       │
│  1. Trigger (Push/PR/Manual)                                         │
│         │                                                             │
│         ▼                                                             │
│  2. Build & Test                                                     │
│     - Maven/Gradle (Java)                                            │
│     - Go build                                                       │
│     - Docker build                                                   │
│         │                                                             │
│         ▼                                                             │
│  3. Push to ECR                                                      │
│     - aws ecr get-login-password                                     │
│     - docker build --platform linux/amd64                            │
│     - docker push 315974965680.dkr.ecr.us-east-1.amazonaws.com      │
│         │                                                             │
│         ▼                                                             │
│  4. Deploy to K3s                                                    │
│     - SSH to Master Node (44.214.64.63)                              │
│     - kubectl set image deployment/<app> <image>:<new-tag>           │
│     - kubectl rollout status deployment/<app>                        │
│         │                                                             │
│         ▼                                                             │
│  5. Health Check                                                     │
│     - kubectl get pods -n oficinapro                                 │
│     - curl http://<pod>:<port>/health                                │
│     - curl http://<pod>:<port>/actuator/health                       │
│         │                                                             │
│         ▼                                                             │
│  6. Notify (Success/Failure)                                         │
│     - Slack notification (opcional)                                  │
│     - Update deployment status                                       │
└──────────────────────────────────────────────────────────────────────┘
```

## 📊 Arquitetura de Observabilidade

### Stack Completo

```
┌────────────────────────────────────────────────────────────────────┐
│                       NEW RELIC APM                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                │
│  │   Traces    │  │  Metrics    │  │    Logs     │                │
│  │  (OTLP)     │  │  (OTLP)     │  │ (Correlated)│                │
│  └─────────────┘  └─────────────┘  └─────────────┘                │
└────────────────────────────────────────────────────────────────────┘
         ▲                  ▲                  ▲
         │                  │                  │
         │    OTLP/HTTP (4318)                 │
         │                  │                  │
┌────────────────────────────────────────────────────────────────────┐
│                   K3s CLUSTER (5 Microserviços)                     │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────┐  │
│  │ Saga     │ │ Billing  │ │ Customer │ │Execution │ │Payment │  │
│  │ (Java)   │ │ (Java)   │ │ (Java)   │ │ (Java)   │ │(Python)│  │
│  │ :8080    │ │ :8082    │ │ :8084    │ │ :8083    │ │ :8000  │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └────────┘  │
│       │             │             │             │            │      │
│       └─────────────┴─────────────┴─────────────┴────────────┘      │
│                              │                                       │
│                              ▼                                       │
│                    ┌──────────────────┐                             │
│                    │  RDS PostgreSQL  │                             │
│                    │  (os_db)         │                             │
│                    └──────────────────┘                             │
└────────────────────────────────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────────────────────────────┐
│                 SERVERLESS (Lambda + API GW)                        │
│  ┌──────────────────┐              ┌──────────────────┐            │
│  │  Auth Service    │              │  Order Service   │            │
│  │  (Go Lambda)     │              │  (Go Lambda)     │            │
│  └──────────────────┘              └──────────────────┘            │
└────────────────────────────────────────────────────────────────────┘
```

### Métricas Monitoradas

**Por Aplicação (New Relic APM):**
- ✅ Request Rate (req/s)
- ✅ Error Rate (%)
- ✅ Latência (P50, P95, P99)
- ✅ Throughput (MB/s)
- ✅ CPU/Memory Usage
- ✅ Database Query Performance

**Por Infraestrutura (CloudWatch + New Relic):**
- ✅ EC2 Instance Health
- ✅ K3s Node Status
- ✅ Pod Status/Restarts
- ✅ ALB Target Health
- ✅ RDS Connections/CPU
- ✅ Lambda Invocations/Errors

## 🛠️ Comandos Úteis

### Kubernetes (K3s)

```bash
# Exportar kubeconfig
export KUBECONFIG=/path/to/k3s-config.yaml

# Verificar nodes
kubectl get nodes -o wide

# Listar todos os pods
kubectl get pods -n oficinapro -o wide

# Ver logs de um pod
kubectl logs -f <pod-name> -n oficinapro

# Descrever pod (troubleshooting)
kubectl describe pod <pod-name> -n oficinapro

# Verificar deployments
kubectl get deployments -n oficinapro

# Verificar services
kubectl get svc -n oficinapro

# Escalar deployment
kubectl scale deployment/<app> --replicas=3 -n oficinapro

# Restart deployment
kubectl rollout restart deployment/<app> -n oficinapro

# Ver histórico de rollout
kubectl rollout history deployment/<app> -n oficinapro

# Health check de um pod
kubectl exec -n oficinapro <pod> -- wget -qO- http://localhost:<port>/health
```

### SSH e Acesso aos Nodes

```bash
# SSH no Master Node
ssh -i ~/.ssh/chave_nova ubuntu@44.214.64.63

# Verificar status do K3s
sudo systemctl status k3s
sudo journalctl -u k3s -n 50 --no-pager

# Verificar recursos
free -h
df -h
top

# SSH no Worker Node (se configurado)
ssh -i ~/.ssh/chave_nova ubuntu@34.228.205.101

# Verificar status do K3s Agent
sudo systemctl status k3s-agent
```

### ECR (Container Registry)

```bash
# Login
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  315974965680.dkr.ecr.us-east-1.amazonaws.com

# Listar repositórios
aws ecr describe-repositories --region us-east-1

# Build e Push (IMPORTANTE: use AMD64 para AWS!)
docker build --platform linux/amd64 -t <app>:latest .
docker tag <app>:latest 315974965680.dkr.ecr.us-east-1.amazonaws.com/<app>:latest
docker push 315974965680.dkr.ecr.us-east-1.amazonaws.com/<app>:latest
```

### Terraform

```bash
# Ver estado atual
terraform show

# Ver outputs
terraform output

# Atualizar um módulo específico
terraform apply -target=aws_instance.k3s_master

# Destruir recursos (CUIDADO!)
terraform destroy

# Forçar unlock do state
terraform force-unlock <LOCK_ID>

# Importar recurso existente
terraform import aws_instance.master i-045c8b690fe628714
```

### Troubleshooting

```bash
# Verificar state lock do Terraform
aws dynamodb scan --table-name oficinapro-tfstate-lock-table --region us-east-1

# Deletar lock manualmente (se necessário)
aws dynamodb delete-item \
  --table-name oficinapro-tfstate-lock-table \
  --key '{"LockID":{"S":"oficinapro/app-infra/terraform.tfstate-md5"}}' \
  --region us-east-1

# Verificar security groups
aws ec2 describe-security-groups --region us-east-1 --query 'SecurityGroups[*].[GroupId,GroupName]'

# Verificar instâncias EC2
aws ec2 describe-instances --region us-east-1 --filters "Name=instance-state-name,Values=running"

# Reboot instância K3s
aws ec2 reboot-instances --instance-ids i-045c8b690fe628714 --region us-east-1
```

## 📦 Outputs da Infraestrutura

### Informações do Cluster K3s

```bash
# No diretório app-infra/
terraform output

# Outputs disponíveis:
# - alb_dns_name
# - k3s_master_public_ip: 44.214.64.63
# - k3s_master_private_ip: 10.1.0.177
# - cluster_api_endpoint: https://44.214.64.63:6443
# - ssh_master_command
```

### Database Connection

```bash
# Host: oficinapro-consolidated-db.cmz0ic48gh2u.us-east-1.rds.amazonaws.com
# Port: 5432
# Database: os_db
# User: oficinapro_admin
# Password: (armazenado em secrets)

# Connection string para Spring Boot:
# jdbc:postgresql://oficinapro-consolidated-db.cmz0ic48gh2u.us-east-1.rds.amazonaws.com:5432/os_db
```

## 🔐 Segurança

### Security Groups

| SG | Nome | Portas Permitidas | Uso |
|----|------|-------------------|-----|
| `sg-0ad0deffa387fa08f` | k3s-sg | 22, 6443, 80, 443 | K3s Nodes |
| `sg-0eec3b20db7084042` | rds-sg | 5432 (from K3s SG) | RDS |

### IAM Roles

| Role | Serviço | Políticas |
|------|---------|-----------|
| `oficinapro-k3s-role-fase4` | EC2 | SSM, ECR, CloudWatch |
| `auth-lambda-role` | Lambda | Logs, DynamoDB |
| `order-lambda-role` | Lambda | Logs, SQS, SNS |

### Secrets Management

**Kubernetes Secrets (K3s):**
- `database-secrets`: Credenciais do RDS
- `newrelic-secrets`: License key New Relic
- `oficinapro-secrets`: MP_TOKEN, DB_PASSWORD
- `ecr-secret`: Credenciais Docker ECR

**GitHub Secrets:**
- Ver seção "Secrets do GitHub Necessários" acima

## 🏛️ Decisões Arquiteturais (ADRs)

### ADR-001: K3s ao invés de EKS

**Contexto:** EKS custa $72/mês apenas pelo control plane.

**Decisão:** Usar K3s (Kubernetes leve) em EC2 instances.

**Consequências:**
- ✅ Economia de ~$72/mês
- ✅ Controle total sobre o cluster
- ⚠️ Responsabilidade por manutenção do control plane
- ⚠️ Single point of failure no Master (mitigado por backups)

### ADR-002: Multi-Node Cluster

**Contexto:** 7 microserviços com diferentes workloads (Java ~1GB RAM cada).

**Decisão:** 
- Master: t3.small (2GB) - control plane isolado
- Worker: t3.small (2GB) - workloads (pode ser escalado)

**Consequências:**
- ✅ Isolamento entre control plane e workloads
- ✅ Melhor utilização de recursos
- ✅ Facilita escalabilidade horizontal
- ⚠️ Custo adicional (~$15/mês por node extra)

### ADR-003: Autenticação Serverless

**Contexto:** Auth service tem padrão de uso bursty.

**Decisão:** Lambda + API Gateway para auth-service e order-service.

**Consequências:**
- ✅ Auto-scaling automático
- ✅ Pay-per-use (~$5/mês)
- ✅ Zero manutenção de infra
- ⚠️ Cold start (~200-500ms)

### ADR-004: New Relic APM

**Contexto:** Necessidade de observabilidade centralizada para múltiplas linguagens.

**Decisão:** New Relic com OpenTelemetry (OTLP).

**Consequências:**
- ✅ Suporte nativo para Java, Go, Python
- ✅ Traces, Metrics e Logs correlacionados
- ✅ Dashboards e Alertas prontos
- ✅ Free tier até 100GB/mês
- ⚠️ Overhead de ~5-10ms por request

## 🐛 Troubleshooting Common Issues

### Issue 1: Terraform State Locked

**Erro:**
```
Error acquiring the state lock
```

**Solução:**
```bash
# Verificar locks
aws dynamodb scan --table-name oficinapro-tfstate-lock-table --region us-east-1

# Force unlock
terraform force-unlock <LOCK_ID>

# Se falhar, deletar manualmente no DynamoDB
aws dynamodb delete-item \
  --table-name oficinapro-tfstate-lock-table \
  --key '{"LockID":{"S":"oficinapro/app-infra/terraform.tfstate-md5"}}' \
  --region us-east-1
```

### Issue 2: SSH Timeout para K3s Nodes

**Erro:**
```
ssh: connect to host 44.214.64.63 port 22: Operation timed out
```

**Verificar:**
```bash
# Status da instância
aws ec2 describe-instances --instance-ids i-045c8b690fe628714 --region us-east-1

# Security Group rules
aws ec2 describe-security-groups --group-ids sg-0ad0deffa387fa08f --region us-east-1

# Reboot se necessário
aws ec2 reboot-instances --instance-ids i-045c8b690fe628714 --region us-east-1
```

### Issue 3: Pods em ImagePullBackOff

**Erro:**
```
Failed to pull image: unauthorized
```

**Solução:**
```bash
# Recriar ecr-secret
kubectl delete secret ecr-secret -n oficinapro
kubectl create secret docker-registry ecr-secret \
  --docker-server=315974965680.dkr.ecr.us-east-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region us-east-1)" \
  --namespace=oficinapro
```

### Issue 4: Database Connection Failed

**Erro:**
```
FATAL: password authentication failed for user "oficinapro_admin"
```

**Verificar:**
```bash
# Ver secrets atuais
kubectl get secret database-secrets -n oficinapro -o yaml

# Recriar com credenciais corretas
kubectl delete secret database-secrets -n oficinapro
kubectl create secret generic database-secrets \
  --from-literal=DB_NAME="os_db" \
  --from-literal=DB_HOST="oficinapro-consolidated-db.cmz0ic48gh2u.us-east-1.rds.amazonaws.com" \
  --from-literal=DB_PORT="5432" \
  --from-literal=DB_USER="oficinapro_admin" \
  --from-literal=DB_USERNAME="oficinapro_admin" \
  --from-literal=DB_PASSWORD="K9fQ7T2mLE8ZxPOficinaPro" \
  --from-literal=SPRING_DATASOURCE_URL="jdbc:postgresql://oficinapro-consolidated-db.cmz0ic48gh2u.us-east-1.rds.amazonaws.com:5432/os_db" \
  --from-literal=SPRING_DATASOURCE_USERNAME="oficinapro_admin" \
  --from-literal=SPRING_DATASOURCE_PASSWORD="K9fQ7T2mLE8ZxPOficinaPro" \
  --namespace=oficinapro

# Restart pods
kubectl rollout restart deployment/<app> -n oficinapro
```

### Issue 5: VPC Mismatch

**Erro:**
```
java.net.UnknownHostException: oficinapro-consolidated-db...
```

**Causa:** K3s e RDS em VPCs diferentes.

**Solução:**
- Verificar que todos os recursos estão em `vpc-0c206d03a5b4bfb6b`
- Se necessário, destruir e recriar K3s cluster
- Atualizar Terraform remote state se necessário

## 📚 Documentação Relacionada

| Documento | Descrição |
|-----------|-----------|
| [FASE4_DEPLOYMENT_SUCCESS.md](/Users/kbmarins/Desktop/Personal/FIAP/FASE4_DEPLOYMENT_SUCCESS.md) | Relatório de deploy bem-sucedido |
| [RESUMO_FINAL_DEPLOYMENT_FASE4.md](/Users/kbmarins/Desktop/Personal/FIAP/RESUMO_FINAL_DEPLOYMENT_FASE4.md) | Resumo executivo completo |
| [PAYMENT_API_DEPLOYMENT_SUCCESS.md](/Users/kbmarins/Desktop/Personal/FIAP/PAYMENT_API_DEPLOYMENT_SUCCESS.md) | Deploy do Payment API |
| [ANALISE_DEPLOYMENT_PAYMENTS.md](/Users/kbmarins/Desktop/Personal/FIAP/ANALISE_DEPLOYMENT_PAYMENTS.md) | Análise arquitetural (Lambda vs K3s) |
| [Core Service Docs](../core-domain-service/docs/) | Documentação completa da aplicação |
| [Database Infra](../OficinaPro-Database/README.md) | Infraestrutura do banco de dados |

## 🔄 Fluxo de Atualização da Infraestrutura

### Modificações na Rede (Network)

```bash
cd network/
# 1. Editar main.tf
# 2. Planejar
terraform plan
# 3. Aplicar
terraform apply
# 4. Verificar outputs
terraform output
```

### Modificações no Cluster (App Infra)

```bash
cd app-infra/
# 1. Editar main.tf
# 2. Planejar
terraform plan
# 3. Aplicar
terraform apply
# 4. Verificar nodes
export KUBECONFIG=/path/to/k3s-config.yaml
kubectl get nodes
```

### Rollback de Infraestrutura

```bash
# 1. Identificar versão anterior no S3
aws s3 ls s3://fiap-oficinapro-ckm-tfstate/oficinapro/app-infra/

# 2. Importar state anterior (se disponível)
aws s3 cp s3://fiap-oficinapro-ckm-tfstate/oficinapro/app-infra/terraform.tfstate.backup ./

# 3. Aplicar destroy + apply
terraform destroy -target=<recurso-problemático>
terraform apply
```

## 💡 Melhores Práticas

### 1. Builds Docker
- **SEMPRE** usar `--platform linux/amd64` ao buildar em Mac M1/M2
- Tagging consistente: `<repo>:<sha>-<timestamp>`
- Usar multi-stage builds para reduzir tamanho
- Scan de vulnerabilidades antes do push

### 2. Deploys Kubernetes
- Usar `imagePullPolicy: Always` para garantir imagem mais recente
- Configurar liveness e readiness probes em todos os pods
- Definir resources (requests/limits) para prevenção de OOMKill
- Usar HPA (Horizontal Pod Autoscaler) para auto-scaling

### 3. Secrets Management
- **NUNCA** commitar secrets no Git
- Usar GitHub Secrets para CI/CD
- Usar Kubernetes Secrets para runtime
- Rotacionar senhas periodicamente

### 4. Monitoramento
- Configurar alertas para erros críticos
- Revisar dashboards semanalmente
- Analisar logs de erro diariamente
- Tune de métricas baseado em uso real

## 👥 Equipe

Desenvolvido para o **Tech Challenge da FIAP** - Fase 4.

---

**Status**: ✅ Produção em K3s AWS  
**Cluster**: 44.214.64.63 (Master) + 34.228.205.101 (Worker)  
**CI/CD**: ✅ GitHub Actions Automatizado  
**Observabilidade**: ✅ New Relic APM  
**Database**: ✅ RDS PostgreSQL Multi-AZ  
**Última atualização**: Fevereiro de 2026
