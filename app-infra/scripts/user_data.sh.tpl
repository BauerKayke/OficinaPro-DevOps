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
EIP_ALLOCATION_ID="${eip_allocation_id}"
PROJECT_NAME="OficinaPro-KaykeBauer" # Nome do repositório para clonar

# Atualizar e instalar dependências essenciais
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl software-properties-common git jq unzip

# Instalar Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io

# Obter IP Público para o TLS SAN
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Instalar K3s (versão otimizada) com TLS SAN para permitir acesso externo
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--docker --disable=traefik --disable=servicelb --tls-san $PUBLIC_IP" sh -

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

# Associar o Elastic IP (garantir que a instância tenha IP fixo)
aws ec2 associate-address --instance-id $(curl -s http://169.254.169.254/latest/meta-data/instance-id) --allocation-id $EIP_ALLOCATION_ID --region $AWS_REGION

# Clonar o repositório da aplicação
# Usando variáveis do shell para evitar conflito com o Terraform
git clone https://$GITHUB_TOKEN@github.com/$GITHUB_REPO.git /app

# Navegar para o diretório de deploy e aplicar os manifestos Kubernetes
cd /app/deployment/kubernetes
./deploy.sh

echo "Bootstrap finalizado com sucesso."
