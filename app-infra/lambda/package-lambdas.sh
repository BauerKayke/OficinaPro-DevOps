#!/bin/bash
#
# Script para empacotar Lambdas
# Execute: ./package-lambdas.sh
#

set -e

echo "📦 Empacotando Lambdas..."

# Lambda Auto Start
cd "$(dirname "$0")"
zip -r k3s-auto-start.zip k3s-auto-start.py
echo "✅ k3s-auto-start.zip criado"

# Lambda Auto Stop
zip -r k3s-auto-stop.zip k3s-auto-stop.py
echo "✅ k3s-auto-stop.zip criado"

echo ""
echo "✅ Lambdas empacotadas com sucesso!"
echo ""
echo "Próximo passo:"
echo "  terraform init"
echo "  terraform plan -out=tfplan"
echo "  terraform apply tfplan"
