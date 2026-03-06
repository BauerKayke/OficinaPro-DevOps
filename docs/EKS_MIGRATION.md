# Migração K3s → EKS (Fase 4)

## Resumo

O cluster Kubernetes foi migrado de **EC2 + K3s** para **EKS** (Elastic Kubernetes Service).

## O que mudou

| Antes (K3s) | Depois (EKS) |
|-------------|--------------|
| EC2 com user_data bootstrap | Cluster gerenciado pela AWS |
| SSH/SSM para deploy | `aws eks update-kubeconfig` + kubectl |
| master_ip, Parameter Store kubeconfig | Cluster name em Parameter Store |
| Verify: SSM/SSH/Parameter Store | Verify: kubectl get nodes |

## Pipelines atualizadas

- **OficinaPro-DevOps**: app-infra (EKS), database-init, apply-nodeport
- **OficinaPro-Customer**: ci-cd-fase4
- **OficinaPro-Billing**: ci-cd-fase4
- **OficinaPro-Payments**: ci-cd-fase4
- **OficinaPro-Execution**: ci-cd-fase4
- **saga-orchestrator**: ci-cd-fase4
- **OficinaPro-KaykeBauer** (core-domain): ci-cd-fase4

## Workflows legados (não atualizados)

- `bootstrap-kubeconfig.yml` (Customer) - obsoleto com EKS
- `debug-k3s-cluster.yml` - marcado como legado; use action=debug no App Infra

## Ordem de execução

1. **App Infra CI/CD** (action=apply) → Cria databases, messaging, EKS
2. **Database Init** → Cria databases lógicos no RDS (job no EKS)
3. **Deploy dos serviços** → saga, billing, execution, customer, payment, core-domain (ci-cd-fase4)

## Parâmetro importante

- `/oficinapro/eks/cluster-name` = `oficinapro-fase4` (criado pelo Terraform EKS)

## Free Tier (t3.micro - 1GB RAM)

Recursos reduzidos ao mínimo para caber em 1 node t3.micro:

| Serviço | Request | Limit | JAVA_TOOL_OPTIONS |
|---------|---------|-------|-------------------|
| saga-orchestrator | 64Mi / 50m | 192Mi / 250m | -Xmx96m -Xms48m |
| billing | 80Mi / 50m | 192Mi / 250m | -Xmx96m -Xms48m |
| execution | 80Mi / 50m | 192Mi / 250m | -Xmx96m -Xms48m |
| customer | 80Mi / 50m | 192Mi / 250m | -Xmx96m -Xms48m |
| payment (Python) | 64Mi / 50m | 128Mi / 250m | - |
| core-domain | 80Mi / 50m | 192Mi / 250m | -Xmx96m -Xms48m |

**Total requests:** ~448Mi (sistema ~400Mi = ~848Mi usado de 1024Mi)

**Ordem de deploy recomendada:** saga → billing → execution → customer → payment → core-domain
