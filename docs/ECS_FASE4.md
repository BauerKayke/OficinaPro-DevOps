# ECS Fase 4 - Migração do EKS

## Motivação

- **EKS + t3.micro**: overhead do control plane (~400Mi) + limite de 4 pods por node deixava pouco espaço para aplicações
- **ECS + 2x t3.micro**: sem control plane pago, ~768Mi disponível por instância (256Mi reservados para o agent)
- **Total**: ~1,5GB para containers, dividido entre 6 serviços

## Arquitetura

```
┌─────────────────────────────────────────────────────────────┐
│  ECS Cluster: oficinapro-fase4                               │
│  Capacity Provider: oficinapro-ec2-fase4 (ASG)               │
├─────────────────────────────────────────────────────────────┤
│  Instance 1 (t3.micro)     │  Instance 2 (t3.micro)          │
│  ~768Mi para tasks         │  ~768Mi para tasks              │
│  - saga-orchestrator       │  - billing                       │
│  - customer                │  - execution                    │
│  - payment                 │  - core-domain                  │
└─────────────────────────────────────────────────────────────┘
```

## Recursos por Serviço (memória controlada)

| Serviço           | memory | memoryReservation | Porta |
|-------------------|--------|-------------------|-------|
| saga-orchestrator | 192    | 64                | 8082  |
| billing           | 192    | 64                | 8082  |
| execution         | 192    | 64                | 8082  |
| customer          | 192    | 64                | 8082  |
| payment           | 128    | 64                | 8080  |
| core-domain       | 192    | 64                | 8082  |

## Provisionamento

1. **App Infra** (push em `fase4/06-ecs/` ou manual):
   - Cluster ECS
   - 2x t3.micro (ASG)
   - Task execution role, log groups
   - Serviços ECS (bootstrap com busybox)
   - SSM: `/oficinapro/ecs/cluster-name`

2. **Pipelines de cada serviço** (próximo passo):
   - Build & push imagem GHCR
   - Registrar nova task definition
   - `aws ecs update-service --force-new-deployment`

## Debug

```bash
# Via workflow_dispatch: action=debug (mostra ECS e EKS)
# Ou manualmente:
CLUSTER=$(aws ssm get-parameter --name "/oficinapro/ecs/cluster-name" --query "Parameter.Value" --output text)
aws ecs list-container-instances --cluster $CLUSTER
aws ecs list-services --cluster $CLUSTER
aws ecs describe-services --cluster $CLUSTER --services saga-orchestrator billing
```

## Migração dos Pipelines

O **EKS foi removido** do app-infra. O compute da Fase 4 é apenas ECS.

### Workflow reutilizável

`OficinaPro-DevOps/.github/workflows/deploy-ecs-service.yml` pode ser chamado pelos serviços:

```yaml
# No ci-cd-fase4.yml de cada serviço
deploy-to-ecs:
  needs: build-and-test
  uses: <ORG>/OficinaPro-DevOps/.github/workflows/deploy-ecs-service.yml@main
  with:
    service_name: saga-orchestrator   # ou billing, execution, customer, payment, core-domain
    image: ghcr.io/${{ env.IMAGE_OWNER }}/saga-orchestrator:${{ github.sha }}
    port: "8084"
    health_path: /actuator/health     # ou /health para payment
    memory: "192"                     # 128 para payment
    env_json: ${{ steps.build-env.outputs.env_json }}
  secrets: inherit
```

O passo `build-env` deve montar o JSON de variáveis (RDS, SQS, etc.) incluindo secrets. Exemplo para saga:

```yaml
- id: build-env
  run: |
    RDS="${{ steps.infra.outputs.rds_host }}"
    # ... buscar SQS ...
    ENV=$(jq -n \
      --arg rds "jdbc:postgresql://${RDS}:5432/saga_db" \
      --arg db "${{ secrets.DB_PASSWORD }}" \
      --arg nr "${{ secrets.NEW_RELIC_LICENSE_KEY }}" \
      '[{"name":"SPRING_DATASOURCE_URL","value":$rds},{"name":"DB_PASSWORD","value":$db},{"name":"NEW_RELIC_LICENSE_KEY","value":$nr},...]')
    echo "env_json<<EOF" >> $GITHUB_OUTPUT
    echo "$ENV" >> $GITHUB_OUTPUT
    echo "EOF" >> $GITHUB_OUTPUT
```

### Mapeamento serviço → ECS

| Repo / Imagem        | ECS service     | Porta | health_path          |
|----------------------|-----------------|-------|----------------------|
| saga-orchestrator    | saga-orchestrator | 8084 | /actuator/health     |
| billing-service      | billing         | 8081 | /actuator/health     |
| execution-service    | execution       | 8083 | /actuator/health     |
| customer-service     | customer        | 8082 | /actuator/health     |
| payment-service      | payment         | 8000 | /health              |
| core-domain-service  | core-domain     | 8080 | /api/v1/actuator/health |

## Próximos Passos

1. Rodar **App Infra** para criar o cluster ECS
2. Adaptar pipelines (saga, billing, execution, customer, payment, KaykeBauer) para deploy ECS em vez de EKS
3. (Opcional) Destruir EKS quando ECS estiver estável: `terraform destroy` em `fase4/05-eks`
