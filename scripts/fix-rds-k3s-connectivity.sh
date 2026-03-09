#!/bin/bash
# Corrige conectividade K3s -> RDS (PostgreSQL 5432)
# Adiciona regra no SG do RDS permitindo o SG do K3s
# Uso: ./scripts/fix-rds-k3s-connectivity.sh [--region us-east-1]

set -e
REGION="${REGION:-us-east-1}"
[[ "$1" == "--region" ]] && REGION="$2"

echo "Region: $REGION"

# SG do K3s (pelo nome)
K3S_SG=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=oficinapro-k3s-cluster-sg-fase4" \
  --query 'SecurityGroups[0].GroupId' --output text --region "$REGION" 2>/dev/null)

# SG do RDS
RDS_SG=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=oficinapro-rds-sg-optimized" \
  --query 'SecurityGroups[0].GroupId' --output text --region "$REGION" 2>/dev/null)

if [[ -z "$K3S_SG" || "$K3S_SG" == "None" ]]; then
  echo "::error::SG K3s não encontrado (oficinapro-k3s-cluster-sg-fase4)"
  exit 1
fi
if [[ -z "$RDS_SG" || "$RDS_SG" == "None" ]]; then
  echo "::error::SG RDS não encontrado (oficinapro-rds-sg-optimized)"
  exit 1
fi

echo "K3s SG:  $K3S_SG"
echo "RDS SG:  $RDS_SG"

# Verificar se regra já existe
EXISTS=$(aws ec2 describe-security-group-rules \
  --filters "Name=group-id,Values=$RDS_SG" "Name=referenced-group-info.group-id,Values=$K3S_SG" "Name=from-port,Values=5432" \
  --query 'SecurityGroupRules[0].SecurityGroupRuleId' --output text --region "$REGION" 2>/dev/null || echo "")

if [[ -n "$EXISTS" && "$EXISTS" != "None" ]]; then
  echo "Regra já existe."
  exit 0
fi

# Adicionar regra
aws ec2 authorize-security-group-ingress \
  --group-id "$RDS_SG" \
  --protocol tcp \
  --port 5432 \
  --source-group "$K3S_SG" \
  --region "$REGION"

echo "Regra adicionada: RDS (5432) <- K3s cluster SG"
echo "Teste novamente: kubectl run -it --rm nettest --image=busybox --restart=Never -n oficinapro-prod -- nc -zv oficinapro-consolidated-db.cmz0ic48gh2u.us-east-1.rds.amazonaws.com 5432 -w 5"
