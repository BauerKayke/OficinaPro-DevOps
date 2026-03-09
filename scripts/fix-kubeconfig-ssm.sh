#!/bin/bash
# Corrige kubeconfig no SSM: remove duplicatas e garante formato correto
set -e
REGION="${1:-us-east-1}"

echo "Buscando kubeconfig do SSM..."
CONTENT=$(aws ssm get-parameter --name "/oficinapro/k3s/kubeconfig" --with-decryption --query "Parameter.Value" --output text --region "$REGION")

# Remove duplicatas: apaga todas insecure-skip-tls-verify e adiciona uma
CONTENT=$(echo "$CONTENT" | sed '/insecure-skip-tls-verify/d' | sed '/server: https:/a\    insecure-skip-tls-verify: true')

echo "Atualizando SSM..."
aws ssm put-parameter --name "/oficinapro/k3s/kubeconfig" --value "$CONTENT" --type "SecureString" --overwrite --region "$REGION"

echo "Salvando em /tmp/kubeconfig..."
echo "$CONTENT" > /tmp/kubeconfig
echo "KUBECONFIG=/tmp/kubeconfig"
echo "Teste: kubectl get pods -n oficinapro-prod"
