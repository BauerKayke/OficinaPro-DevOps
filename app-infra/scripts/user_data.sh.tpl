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

# ====================================================================
# GARANTIR QUE SSH PERMANECE ACESSÍVEL (CRÍTICO PARA CI/CD)
# ====================================================================
echo "Configurando firewall para garantir acesso SSH..."

# Desabilitar ufw se estiver ativo (conflita com K3s)
systemctl stop ufw || true
systemctl disable ufw || true

# Garantir que o SSH service está rodando e habilitado
systemctl enable ssh
systemctl start ssh
systemctl status ssh

# Verificar que a porta 22 está escutando
ss -tlnp | grep :22 || echo "AVISO: SSH não está escutando na porta 22!"

echo "SSH configurado e verificado."
# ===================================================================="

# Instalar K3s (versão otimizada) com TLS SAN para permitir acesso externo
# Removido --docker para usar containerd (nativo e mais estável)
echo "Baixando instalador K3s..."
curl -sfL https://get.k3s.io -o install.sh
chmod +x install.sh

echo "Executando instalador K3s..."
INSTALL_K3S_EXEC="--disable=traefik --disable=servicelb --tls-san $PUBLIC_IP" ./install.sh

# Verificar se instalou
if ! systemctl is-active --quiet k3s; then
    echo "ERRO CRÍTICO: K3s não iniciou!"
    exit 1
fi

echo "K3s instalado com sucesso."

# ====================================================================
# VERIFICAR NOVAMENTE QUE SSH AINDA ESTÁ ACESSÍVEL PÓS K3S
# ====================================================================
echo "Verificando acesso SSH pós-instalação do K3s..."
systemctl status ssh
ss -tlnp | grep :22 || echo "ERRO: SSH não está mais acessível!"

# Se K3s modificou iptables, garantir que SSH continua permitido
iptables -L INPUT -n | grep "dpt:22" || {
    echo "Adicionando regra iptables para SSH..."
    iptables -I INPUT -p tcp --dport 22 -j ACCEPT
}
# ===================================================================="

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

# Instalar Nginx Ingress Controller (Bare Metal)
echo "Instalando Nginx Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/baremetal/deploy.yaml

# Aguardar o deployment ser criado
sleep 10

# Patch para usar hostNetwork: true (para ouvir nas portas 80/443 do EC2)
kubectl patch deployment ingress-nginx-controller -n ingress-nginx --patch '{"spec": {"template": {"spec": {"hostNetwork": true}}}}'

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

# Instalar Kustomize (necessário para deploy.sh)
echo "Instalando Kustomize..."
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
mv kustomize /usr/local/bin/
chmod +x /usr/local/bin/kustomize

# Clonar o repositório da aplicação
# Usando variáveis do shell para evitar conflito com o Terraform
git clone https://$GITHUB_TOKEN@github.com/$GITHUB_REPO.git /app

# Navegar para o diretório de deploy e aplicar os manifestos Kubernetes
cd /app/deployment/kubernetes
chmod +x deploy.sh

# Exportar variáveis de ambiente necessárias para deploy.sh
export SPRING_DATASOURCE_PASSWORD="$DB_PASSWORD"
export SPRING_DATA_REDIS_PASSWORD="redis-senha-dummy"  # Placeholder
export JWT_SECRET="oficinapro-jwt-secret-key-2024"
export JWT_EXPIRATION="86400000"  # 24 horas
export SPRING_MAIL_PASSWORD="mail-senha-dummy"  # Placeholder
export NEW_RELIC_LICENSE_KEY="dummy-license-key"  # Placeholder (será fornecido via CI/CD)
export DB_HOST="$DB_HOST"
export API_BASE_URL="https://example.com"  # Placeholder (será atualizado via CI/CD)

# Executar deploy
./deploy.sh dev apply

echo "Bootstrap finalizado com sucesso."
