# Troubleshooting: Cluster K3s não fica operacional (Fase 4)

## Diagnóstico realizado

### Sintomas

| Sintoma | Observado | Implicação |
|--------|-----------|------------|
| Porta 22 (SSH) | Timeout de fora (GitHub Runner) | Tráfego não chega na instância |
| SSM send-command | Retorna CommandId (aceito) | API AWS OK |
| SSM get-command-invocation | Status: **Failed**, Details: **Undeliverable** | Comando NÃO foi entregue à instância |
| Security Group | Porta 22: 0.0.0.0/0 | SG está correto |
| Console output | Boot OK, SSM Agent running, cloud-init finished | VM inicializou |
| user_data | apt upgrade + K3s + nginx-ingress | ~10-15 min total |

### Causa raiz: SSM Undeliverable

Segundo a [documentação AWS](https://docs.aws.amazon.com/systems-manager/latest/userguide/monitor-commands.html):

> **Undeliverable**: The command can't be delivered to the managed node. The node might not exist or it might not be responding.

Ou seja: o SSM **não consegue entregar** o comando à instância. Motivos comuns:

1. **Instância não registrada no Fleet Manager** – O SSM Agent não estabeleceu conexão bidirecional com o serviço AWS.
2. **Instância sem saída para endpoints SSM** – O agente precisa de conectividade outbound para:
   - `ssm.us-east-1.amazonaws.com`
   - `ec2messages.us-east-1.amazonaws.com`
   - `ssmmessages.us-east-1.amazonaws.com`
3. **apt-get upgrade bloqueando** – Durante o upgrade (10–15 min), alta carga e locks podem atrasar o registro do SSM.
4. **Timeout de entrega** – O comando expira antes de o nó responder.

---

## Alternativas e correções

### Opção 1: VPC Endpoints para SSM (recomendado)

Criar **interface endpoints** na VPC para SSM remove a necessidade de saída para internet para o agente se comunicar com o SSM.

Endpoints necessários:

- `com.amazonaws.us-east-1.ssm`
- `com.amazonaws.us-east-1.ec2messages`
- `com.amazonaws.us-east-1.ssmmessages`

**Vantagens:** SSM passa a funcionar mesmo sem internet na instância; entrega de comandos mais estável.  
**Custo:** ~US$ 22/mês (3 endpoints × ~US$ 7,20).

---

### Opção 2: Simplificar o user_data (recomendado)

O `apt-get upgrade -y` pode levar 10–15 min e bloquear o boot.

Alterações sugeridas:

- Remover `apt-get upgrade -y` no primeiro boot; ou
- Rodar upgrade em background:  
  `(apt-get upgrade -y &)` e continuar com o K3s em paralelo.

**Efeito:** Boot mais rápido e SSM pode registrar enquanto o K3s instala.

---

### Opção 3: Verificar conectividade outbound

Se a instância não tiver saída para a internet, o SSM não registra. Conferir:

- Route table da subnet pública: `0.0.0.0/0` → Internet Gateway
- Security Group da instância: egress `0.0.0.0/0`
- NACL: regras de tráfego permitidas
- DNS: `enable_dns_support` e `enable_dns_hostnames` na VPC

---

### Opção 4: Deploy via kubectl (porta 6443)

O Security Group já permite `6443` de `0.0.0.0/0` para o K3s API.

Se o K3s subir e o `user_data` gravar o kubeconfig no Parameter Store, o GitHub Runner pode usar `kubectl` direto contra `https://<MASTER_IP>:6443`.

**Limitação:** O kubeconfig só é gravado quando o `user_data` termina; hoje o fluxo trava antes disso.

---

### Opção 5: Abrir porta 22 e corrigir rede

Se a porta 22 continuar com timeout mesmo com SG em `0.0.0.0/0`, investigar:

- Se a instância está na subnet correta (pública)
- Se há algum proxy/firewall entre o GitHub e a AWS
- Se o Elastic IP está associado corretamente
- Rotas e NACLs

---

## Plano de ação (implementado)

1. ✅ **VPC Endpoints para SSM** – Adicionados no módulo compute (`ssm`, `ec2messages`, `ssmmessages`).
2. ✅ **Simplificar user_data** – Removido `apt-get upgrade`; awscli via apt (mais rápido que snap).
3. ✅ **Bootstrap via Parameter Store** – `user_data` grava `/oficinapro/k3s/bootstrap-status` a cada etapa; Verify faz **polling** nesse parâmetro, sem depender de SSH ou SSM Run Command.
4. ✅ **Debug ampliado** – `describe-instance-information` + bootstrap-status no output.

---

## Comandos de verificação manual

```bash
# Ver se a instância está registrada no SSM
aws ssm describe-instance-information --filters "Key=InstanceIds,Values=i-XXXXX"

# Ver regras do SG
aws ec2 describe-security-groups --group-ids sg-XXXXX

# Console da instância
aws ec2 get-console-output --instance-id i-XXXXX
```
