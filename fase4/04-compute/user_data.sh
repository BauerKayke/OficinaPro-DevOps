#!/bin/bash
# Bootstrap K3s - com status via Parameter Store para Verify sem SSH/SSM
set -e
REGION="us-east-1"
PARAM_STATUS="/oficinapro/k3s/bootstrap-status"

report() {
  command -v aws >/dev/null && aws ssm put-parameter --name "$PARAM_STATUS" --value "$1" --type "String" --overwrite --region "$REGION" 2>/dev/null || true
}

# Deps (apt awscli é mais rápido que snap)
apt-get update
apt-get install -y curl wget apt-transport-https ca-certificates gnupg lsb-release awscli
report "deps_ready"

hostnamectl set-hostname ${hostname}

# K3s
report "k3s_installing"
curl -sfL https://get.k3s.io | sh -s - \
  --write-kubeconfig-mode 644 \
  --disable traefik \
  --node-name ${hostname}

until kubectl get nodes 2>/dev/null; do sleep 5; done
report "k3s_ready"

kubectl create namespace oficinapro-prod || true

# Nginx Ingress (cluster já funciona; ingress é opcional para Verify)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/baremetal/deploy.yaml 2>/dev/null || true
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s 2>/dev/null || true
kubectl patch service ingress-nginx-controller -n ingress-nginx --type='json' -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":30080}]' 2>/dev/null || true

# Kubeconfig no Parameter Store
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
