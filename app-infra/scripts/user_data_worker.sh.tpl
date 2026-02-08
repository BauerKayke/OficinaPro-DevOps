#!/bin/bash
set -e

# Configurar hostname
hostnamectl set-hostname k3s-worker-01

# Instalar utilitários
apt-get update
apt-get install -y curl unzip awscli jq

# Obter Região
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

echo "Aguardando parâmetros do Master no SSM..."

# Loop para buscar o Token e o IP do Master (espera o Master subir)
MAX_RETRIES=30
COUNT=0
while [ $COUNT -lt $MAX_RETRIES ]; do
    MASTER_IP=$(aws ssm get-parameter --name "/oficinapro/k3s/master-ip" --query "Parameter.Value" --output text --region "$REGION" || echo "")
    TOKEN=$(aws ssm get-parameter --name "/oficinapro/k3s/token" --with-decryption --query "Parameter.Value" --output text --region "$REGION" || echo "")

    if [ -n "$MASTER_IP" ] && [ -n "$TOKEN" ] && [ "$MASTER_IP" != "None" ]; then
        echo "Parâmetros encontrados!"
        break
    fi

    echo "Aguardando Master inicializar... (Tentativa $COUNT/$MAX_RETRIES)"
    sleep 10
    COUNT=$((COUNT+1))
done

if [ -z "$MASTER_IP" ] || [ -z "$TOKEN" ]; then
    echo "ERRO: Não foi possível obter credenciais do Master após várias tentativas."
    exit 1
fi

# Instalar K3s (Agent/Worker)
# Conecta ao Master usando o IP e Token recuperados
curl -sfL https://get.k3s.io | K3S_URL=https://$MASTER_IP:6443 K3S_TOKEN=$TOKEN sh -s - agent --node-label role=worker

echo "Worker K3s inicializado e conectado ao cluster!"
