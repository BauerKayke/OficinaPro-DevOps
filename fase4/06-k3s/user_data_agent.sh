#!/bin/bash
# K3s Agent - worker node
set -e

apt-get update
apt-get install -y curl

hostnamectl set-hostname ${hostname}

# Aguardar server estar acessível
for i in $(seq 1 30); do
  if curl -sk "${server_url}/healthz" 2>/dev/null | grep -q "ok"; then
    break
  fi
  sleep 10
done

curl -sfL https://get.k3s.io | sh -s - agent \
  --server "${server_url}" \
  --token "${k3s_token}" \
  --node-name ${hostname}
