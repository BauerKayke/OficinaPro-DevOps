#!/bin/bash
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install dependencies
apt-get install -y curl wget apt-transport-https ca-certificates gnupg lsb-release

# Set hostname
hostnamectl set-hostname ${hostname}

# Install K3s
curl -sfL https://get.k3s.io | sh -s - \
  --write-kubeconfig-mode 644 \
  --disable traefik \
  --node-name ${hostname}

# Wait for K3s to be ready
until kubectl get nodes 2>/dev/null; do
  echo "Waiting for K3s to be ready..."
  sleep 5
done

# Create namespaces
kubectl create namespace oficinapro-prod || true

# Install AWS CLI
snap install aws-cli --classic

# Install Nginx Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/baremetal/deploy.yaml

# Wait for Ingress Controller to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# Patch Ingress Controller Service to use NodePort 30080
kubectl patch service ingress-nginx-controller -n ingress-nginx --type='json' -p='[{"op": "replace", "path": "/spec/ports/0/nodePort", "value": 30080}]'

echo "✅ K3s installation complete!"
