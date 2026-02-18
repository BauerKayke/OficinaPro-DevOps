#!/bin/bash
set -e

# Versão do script: ${scripts_version}
# ROLE: K3S MASTER (Server)

# Variáveis do Terraform
GITHUB_REPO="${github_repo}"
GITHUB_TOKEN="${github_token}"
AWS_REGION="${aws_region}"
DB_HOST="${db_host}"
DB_NAME="${db_name}"
DB_USERNAME="${db_username}"
DB_PASSWORD="${db_password}"
PUBLIC_IP="${public_ip}"

echo "🚀 Iniciando bootstrap do K3s MASTER..."

# Atualizar e instalar dependências essenciais
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl software-properties-common git jq unzip

# ====================================================================
# GARANTIR QUE SSH PERMANECE ACESSÍVEL
# ====================================================================
echo "🔐 Configurando SSH..."
systemctl stop ufw || true
systemctl disable ufw || true
systemctl enable ssh
systemctl start ssh
systemctl status ssh
ss -tlnp | grep :22 || echo "AVISO: SSH não está escutando na porta 22!"
echo "✅ SSH configurado"

# ====================================================================
# INSTALAR K3S COMO SERVER (MASTER)
# ====================================================================
echo "📦 Instalando K3s Server..."
curl -sfL https://get.k3s.io -o install.sh
chmod +x install.sh

# Instalar como server com TLS SAN para acesso externo
INSTALL_K3S_EXEC="server --disable=traefik --disable=servicelb --tls-san $PUBLIC_IP --node-label role=master" ./install.sh

# Verificar se instalou
if ! systemctl is-active --quiet k3s; then
    echo "❌ ERRO CRÍTICO: K3s não iniciou!"
    exit 1
fi

echo "✅ K3s Server instalado com sucesso"

# Verificar SSH pós-instalação
echo "🔍 Verificando SSH pós-instalação..."
systemctl status ssh
ss -tlnp | grep :22 || echo "ERRO: SSH não está mais acessível!"

# Garantir regra iptables para SSH
iptables -L INPUT -n | grep "dpt:22" || {
    echo "Adicionando regra iptables para SSH..."
    iptables -I INPUT -p tcp --dport 22 -j ACCEPT
}

# Aguardar K3s ficar pronto
echo "⏳ Aguardando K3s inicializar (30s)..."
sleep 30

# Configurar kubeconfig para root
mkdir -p /root/.kube
cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
chmod 600 /root/.kube/config
export KUBECONFIG=/root/.kube/config

# Configurar kubeconfig para ubuntu (para SCP)
mkdir -p /home/ubuntu/.kube
cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube
chmod 600 /home/ubuntu/.kube/config

# ====================================================================
# INSTALAR FERRAMENTAS
# ====================================================================
echo "🔧 Instalando ferramentas..."

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Kustomize
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
mv kustomize /usr/local/bin/
chmod +x /usr/local/bin/kustomize

echo "✅ Ferramentas instaladas"

# ====================================================================
# INSTALAR NGINX INGRESS CONTROLLER
# ====================================================================
echo "🌐 Instalando Nginx Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/baremetal/deploy.yaml

# Aguardar deployment ser criado
sleep 10

# Patch para usar hostNetwork (ouvir nas portas 80/443 do EC2)
kubectl patch deployment ingress-nginx-controller -n ingress-nginx --patch '{"spec": {"template": {"spec": {"hostNetwork": true}}}}'

echo "✅ Nginx Ingress instalado"

# ====================================================================
# CLONAR REPOSITÓRIO E APLICAR MANIFESTS (OPCIONAL)
# ====================================================================
# Comentado para permitir deploy via CI/CD
# echo "📦 Clonando repositório..."
# git clone https://$GITHUB_TOKEN@github.com/$GITHUB_REPO.git /app

# ====================================================================
# CRIAR NAMESPACE PADRÃO
# ====================================================================
echo "📁 Criando namespace oficinapro-prod..."
kubectl create namespace oficinapro-prod || true

echo "✅ Bootstrap do K3s MASTER finalizado com sucesso!"
echo "📋 Informações:"
echo "  - Node Role: master"
echo "  - API Server: https://$PUBLIC_IP:6443"
echo "  - Token disponível em: /var/lib/rancher/k3s/server/node-token"
