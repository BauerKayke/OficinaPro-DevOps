#!/bin/bash
# K3s Server - versão mais leve de Kubernetes
set -e
REGION="us-east-1"
PARAM_STATUS="/oficinapro/k3s/bootstrap-status"

report() {
  command -v aws >/dev/null && aws ssm put-parameter --name "$PARAM_STATUS" --value "$1" --type "String" --overwrite --region "$REGION" 2>/dev/null || true
}

apt-get update
apt-get install -y curl awscli
report "deps_ready"

hostnamectl set-hostname ${hostname}

report "k3s_installing"
curl -sfL https://get.k3s.io | sh -s - server \
  --token "${k3s_token}" \
  --write-kubeconfig-mode 644 \
  --disable traefik \
  --node-name ${hostname} \
  --tls-san $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost")

until kubectl get nodes 2>/dev/null; do sleep 5; done
report "k3s_ready"

kubectl create namespace oficinapro-prod 2>/dev/null || true

# Kubeconfig no Parameter Store (para pipelines kubectl)
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
if [ -n "$PUBLIC_IP" ] && [ -f /etc/rancher/k3s/k3s.yaml ]; then
  KUBECONFIG_CONTENT=$(sed "s/127.0.0.1/$PUBLIC_IP/g" /etc/rancher/k3s/k3s.yaml)
  aws ssm put-parameter --name "/oficinapro/k3s/kubeconfig" \
    --value "$KUBECONFIG_CONTENT" \
    --type "SecureString" \
    --overwrite \
    --region "$REGION" 2>/dev/null || true
fi

report "complete"
