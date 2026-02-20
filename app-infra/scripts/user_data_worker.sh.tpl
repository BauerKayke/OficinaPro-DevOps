#!/bin/bash
set -e

# Versão do script: ${scripts_version}
# ROLE: K3S WORKER (Agent)

# Variáveis do Terraform
MASTER_PRIVATE_IP="${master_private_ip}"
AWS_REGION="${aws_region}"
PUBLIC_IP="${public_ip}"

echo "🚀 Iniciando bootstrap do K3s WORKER..."

# Atualizar e instalar dependências essenciais
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl software-properties-common jq

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
# INSTALAR FERRAMENTAS BÁSICAS
# ====================================================================
echo "🔧 Instalando AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

echo "✅ Ferramentas instaladas"

# ====================================================================
# AGUARDAR MASTER ESTAR PRONTO
# ====================================================================
echo "⏳ Aguardando Master estar disponível..."
echo "Master IP: $MASTER_PRIVATE_IP"

# Aguardar porta 6443 do Master ficar acessível
for i in {1..60}; do
  if timeout 5 bash -c "cat < /dev/null > /dev/tcp/$MASTER_PRIVATE_IP/6443" 2>/dev/null; then
    echo "✅ Master disponível na porta 6443!"
    break
  fi
  
  if [ $i -eq 60 ]; then
    echo "❌ ERRO: Timeout aguardando Master"
    exit 1
  fi
  
  echo "Tentativa $i/60... aguardando 10s"
  sleep 10
done

# ====================================================================
# NOTA: K3S AGENT SERÁ INSTALADO VIA NULL_RESOURCE
# ====================================================================
# A instalação do K3s agent será feita via SSH pelo Terraform
# após obter o token do Master, pois:
# 1. O token só está disponível APÓS o Master inicializar
# 2. É mais confiável fazer via null_resource com retry

echo "✅ Bootstrap do K3s WORKER (preparação) finalizado!"
echo "📋 Próximo passo: Terraform irá instalar o K3s agent via SSH"
echo "   usando o token do Master"
