# 🔑 SSH Keys - OficinaPro

Este diretório contém backups das chaves SSH para acesso ao cluster K3s.

## 📁 Arquivos

- `oficinapro-master-key-v13` - Chave privada (ED25519)
- `oficinapro-master-key-v13.pub` - Chave pública (ED25519)
- `SSH_KEY_INFO.md` - Documentação completa da chave

## 🚀 Uso Rápido

```bash
# Conectar ao Master
ssh -i ~/.ssh/oficinapro-master-key-v13 ubuntu@44.214.64.63

# Ou copiar a chave para ~/.ssh/ se não estiver lá
cp oficinapro-master-key-v13 ~/.ssh/
chmod 600 ~/.ssh/oficinapro-master-key-v13
```

## ⚠️ SEGURANÇA

**NUNCA commite este diretório no Git!**

O `.gitignore` já está configurado para ignorar:
- `*.pem`
- Chaves privadas

Se você ver este arquivo no Git, algo está errado!

## 🔒 Permissões Corretas

```bash
chmod 600 oficinapro-master-key-v13      # Privada (somente você pode ler)
chmod 644 oficinapro-master-key-v13.pub  # Pública (todos podem ler)
```

---

**Leia `SSH_KEY_INFO.md` para mais detalhes!**
