# Arquitetura Fase 4 - K3s em EC2

## Resumo

O cluster usa **K3s** (versão mais leve de Kubernetes) em **EC2** (2x t3.micro).
Kubernetes é requisito obrigatório; K3s atende com menor overhead que EKS ou K8s completo.

## Arquitetura atual

| Componente | Descrição |
|------------|-----------|
| **K3s** | Kubernetes leve (~50MB binary, SQLite, sem etcd separado) |
| **EC2** | 2x t3.micro: 1 server (control plane) + 1 agent (worker) |
| **Deploy** | kubeconfig no SSM `/oficinapro/k3s/kubeconfig` |
| **Pipelines** | kubectl apply (ConfigMap, Secret, Deployment, Service) |

## Módulo Terraform

- **fase4/06-k3s/** - Cluster K3s (substitui 06-ecs)
- SSM: `/oficinapro/k3s/master-ip`, `/oficinapro/k3s/kubeconfig`, `/oficinapro/k3s/bootstrap-status`

## Pipelines atualizadas (deploy K3s)

- **OficinaPro-DevOps**: app-infra (K3s)
- **saga-orchestrator**: ci-cd-fase4
- **OficinaPro-Billing**: ci-cd-fase4
- **OficinaPro-Execution**: ci-cd-fase4
- **OficinaPro-Customer**: ci-cd-fase4
- **OficinaPro-Payments**: ci-cd-fase4
- **OficinaPro-KaykeBauer** (core-domain): ci-cd-fase4

## Ordem de execução

1. **App Infra CI/CD** (action=apply) → databases, messaging, K3s cluster
2. **Deploy dos serviços** → saga → billing → execution → customer → payment → core-domain

## Memória (2x t3.micro = ~768Mi/instância para workloads)

| Serviço | memory | Porta |
|---------|--------|-------|
| saga-orchestrator | 192Mi | 8084 |
| billing | 192Mi | 8081 |
| execution | 192Mi | 8083 |
| customer | 192Mi | 8082 |
| payment (Python) | 128Mi | 8000 |
| core-domain | 192Mi | 8080 |

**Ordem de deploy recomendada:** saga → billing → execution → customer → payment → core-domain
