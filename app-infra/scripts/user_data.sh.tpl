#!/bin/bash
set -e

# Versão do script: ${scripts_version}

# Variáveis do Terraform
GITHUB_REPO="${github_repo}"
GITHUB_TOKEN="${github_token}"
AWS_REGION="${aws_region}"
DB_HOST="${db_host}"
DB_NAME="${db_name}"
DB_USERNAME="${db_username}"
DB_PASSWORD="${db_password}"
INSTANCE_TYPE="${instance_type}"
# EIP_ALLOCATION_ID não é mais necessário aqui pois o Terraform associa
# PROJECT_NAME="OficinaPro-KaykeBauer" # Removido se não for usado

# IP Público fixo injetado pelo Terraform (EIP)
PUBLIC_IP="${public_ip}"

# Atualizar e instalar dependências essenciais
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl software-properties-common git jq unzip

# Instalar dependências essenciais (removendo Docker que está quebrando o script)
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl software-properties-common git jq unzip

# Instalar K3s (versão otimizada) com TLS SAN para permitir acesso externo
# Removido --docker para usar containerd (nativo e mais estável)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik --disable=servicelb --tls-san $PUBLIC_IP" sh -

# Aguardar o K3s ficar pronto
sleep 30
mkdir -p /root/.kube
cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
chmod 600 /root/.kube/config
export KUBECONFIG=/root/.kube/config

# Configurar acesso para o usuário ubuntu (para permitir SCP)
mkdir -p /home/ubuntu/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube
chmod 600 /home/ubuntu/.kube/config

# Instalar kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Instalar Helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# Instalar AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Clonar o repositório da aplicação
# Usando variáveis do shell para evitar conflito com o Terraform
git clone https://$GITHUB_TOKEN@github.com/$GITHUB_REPO.git /app

# Navegar para o diretório de deploy e aplicar os manifestos Kubernetes
cd /app/deployment/kubernetes
./deploy.sh

echo "Bootstrap finalizado com sucesso."
