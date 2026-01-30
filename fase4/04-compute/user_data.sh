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

echo "✅ K3s installation complete!"
