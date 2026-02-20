# 🔧 Scripts de Observabilidade

Scripts automatizados para deploy e teste de OpenTelemetry na OficinaPro.

---

## 📋 Scripts Disponíveis

### 1. `deploy_observability.sh` ⭐

**Função:** Deploy automatizado de OpenTelemetry no K8s

**O que faz:**
- ✅ Cria Secret `newrelic-credentials`
- ✅ Cria 6 ConfigMaps OTEL (um por serviço)
- ✅ Atualiza deployments com env vars OTEL
- ✅ Restart todos os deployments
- ✅ Aguarda rollout completar
- ✅ Mostra logs OpenTelemetry

**Uso:**
```bash
./deploy_observability.sh
```

**Pré-requisitos:**
- `kubectl` configurado e conectado ao cluster
- Namespace `oficinapro-dev` existente
- Deployments dos serviços já criados

---

### 2. `test_e2e_trace.sh` ⭐

**Função:** Teste end-to-end com validação de trace propagation

**O que faz:**
- ✅ Autentica no Lambda Auth
- ✅ Valida token JWT
- ✅ Lista Ordens de Serviço (Core Domain)
- ✅ Cria pagamento PIX (Payment API)
- ✅ Verifica OS atualizada
- ✅ Health checks de todos os serviços
- ✅ Mostra instruções para New Relic

**Uso:**
```bash
./test_e2e_trace.sh
```

**Pré-requisitos:**
- `curl` instalado
- `jq` instalado
- Lambda Auth funcionando
- Serviços K8s rodando

---

## 🚀 Quick Start

```bash
# 1. Tornar scripts executáveis (se necessário)
chmod +x *.sh

# 2. Deploy observabilidade
./deploy_observability.sh

# 3. Aguardar 2-3 minutos

# 4. Testar fluxo E2E
./test_e2e_trace.sh

# 5. Verificar New Relic
# https://one.newrelic.com → APM & Services
```

---

## 📊 Saída Esperada

### deploy_observability.sh:

```
========================================
  DEPLOY DE OBSERVABILIDADE OFICINAPRO
========================================

1️⃣  Verificando contexto Kubernetes...
   Contexto atual: k3s-context
   ✅ Namespace oficinapro-dev encontrado

2️⃣  Criando/atualizando Secret New Relic...
   ✅ Secret newrelic-credentials criado/atualizado

3️⃣  Criando ConfigMaps de OpenTelemetry...
   ✅ ConfigMap core-domain-otel-config criado
   ✅ ConfigMap saga-otel-config criado
   ✅ ConfigMap billing-otel-config criado
   ✅ ConfigMap customer-otel-config criado
   ✅ ConfigMap execution-otel-config criado
   ✅ ConfigMap payment-otel-config criado

4️⃣  Atualizando deployments com variáveis OTEL...
   ✅ core-domain-service atualizado
   ✅ payment-service atualizado
   ✅ saga-orchestrator atualizado
   ✅ billing-service atualizado
   ✅ customer-service atualizado
   ✅ execution-service atualizado

5️⃣  Aguardando rollout dos deployments...
   ✅ core-domain-service pronto
   ✅ payment-service pronto
   ...

========================================
  ✅ DEPLOY COMPLETO!
========================================
```

### test_e2e_trace.sh:

```
========================================
  TESTE END-TO-END COM TRACE PROPAGATION
========================================

1️⃣  Autenticando no Lambda Auth...
   ✅ Login OK
   Token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
   User ID: 1
   Role: ADMIN

2️⃣  Validando token JWT...
   ✅ Token válido

3️⃣  Listando Ordens de Serviço no Core Domain...
   ✅ Listagem OK
   Total de OS: 5
   Primeira OS: OS-2024-001 (ID: 1)

4️⃣  Criando pagamento PIX no Payment API...
   ✅ Pagamento criado
   Transaction ID: 12345

5️⃣  Verificando OS atualizada...
   ✅ OS encontrada

6️⃣  Verificando health checks...
   Lambda Auth: ✅ healthy
   Core Domain: ✅ UP
   Payment API: ✅ healthy
   Saga: ✅ UP
   Billing: ✅ UP
   Customer: ✅ UP
   Execution: ✅ UP

========================================
  🎉 TESTE END-TO-END COMPLETO!
========================================
```

---

## 🐛 Troubleshooting

### Script não tem permissão de execução

```bash
chmod +x deploy_observability.sh
chmod +x test_e2e_trace.sh
```

### Erro: "kubectl: command not found"

```bash
# Verificar se kubectl está instalado
which kubectl

# Se não estiver, instalar
brew install kubectl  # macOS
```

### Erro: "jq: command not found"

```bash
# Instalar jq
brew install jq  # macOS
apt-get install jq  # Linux
```

### Erro: "namespace not found"

```bash
# Criar namespace
kubectl create namespace oficinapro-dev
```

### Erro: "deployment not found"

O deployment do serviço ainda não foi criado. Verifique se os pods estão rodando:

```bash
kubectl get deployments -n oficinapro-dev
```

---

## 📚 Documentação Relacionada

- [`../OBSERVABILITY_IMPLEMENTATION_PLAN.md`](../OBSERVABILITY_IMPLEMENTATION_PLAN.md) - Plano completo
- [`../OTEL_JAVA_IMPLEMENTATION_GUIDE.md`](../OTEL_JAVA_IMPLEMENTATION_GUIDE.md) - Guia Java
- [`../OBSERVABILITY_DOCS_INDEX.md`](../OBSERVABILITY_DOCS_INDEX.md) - Índice geral

---

**Última atualização:** 16 de fevereiro de 2026
