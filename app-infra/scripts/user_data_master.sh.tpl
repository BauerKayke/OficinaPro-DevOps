#!/bin/bash
set -e

# Configurar hostname
hostnamectl set-hostname k3s-master

# Instalar utilitários
apt-get update
apt-get install -y curl unzip awscli jq

# Instalar K3s (Server/Master)
# Desabilita traefik (usaremos Nginx depois) e servicelb se formos usar ALB externo, 
# mas aqui manteremos simples. O importante é o node-label.
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --node-label role=master --disable traefik" sh -

# Aguardar o token ser gerado
while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
  echo "Aguardando token do K3s..."
  sleep 2
done

# Salvar Token no SSM Parameter Store para o Worker ler
TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

aws ssm put-parameter \
    --name "/oficinapro/k3s/token" \
    --value "$TOKEN" \
    --type "SecureString" \
    --overwrite \
    --region "$REGION"

# Salvar IP Privado do Master no SSM
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
aws ssm put-parameter \
    --name "/oficinapro/k3s/master-ip" \
    --value "$PRIVATE_IP" \
    --type "String" \
    --overwrite \
    --region "$REGION"

echo "Master K3s inicializado com sucesso!"
