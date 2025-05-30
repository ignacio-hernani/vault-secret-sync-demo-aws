# Quick Start Guide

Get the HashiCorp Vault Enterprise Secret Sync demo running in under 5 minutes.

## Prerequisites Checklist

- [ ] HashiCorp Vault CLI installed
- [ ] AWS CLI installed and configured
- [ ] Docker Desktop running
- [ ] Valid Vault Enterprise license file (`vault.hclic`)

## 3-Step Demo

### 1. Start Vault Enterprise
```bash
./vault.sh
```

### 2. Set Up Demo Environment
```bash
./setup-demo.sh
```

### 3. Run the Demo
```bash
./demo.sh
```

## What You'll See

1. **Secret Creation**: Database credentials stored in Vault's KV v2 engine
2. **Automatic Sync**: Secrets automatically appear in AWS Secrets Manager
3. **Real-time Updates**: Changes in Vault instantly sync to AWS
4. **Application Integration**: See how apps use AWS SDKs to access Vault-managed secrets

## Key Commands

| Action | Command |
|--------|---------|
| Check Vault status | `vault status` |
| View secret in Vault | `vault kv get demo-secrets/database` |
| List AWS secrets | `aws secretsmanager list-secrets` |
| Get AWS secret value | `aws secretsmanager get-secret-value --secret-id "vault-kv_demo-secrets-database"` |

## Clean Up
```bash
./cleanup-demo.sh
```

## Need Help?

- **Troubleshooting**: See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
- **Full Guide**: See [README.md](./README.md)
- **Documentation**: [Vault Secret Sync Docs](https://developer.hashicorp.com/vault/docs/sync)

## Architecture at a Glance

```
Vault KV v2  ──sync──▶  AWS Secrets Manager  ──SDK──▶  Your Apps
    ▲                           ▲
    │                           │
  Admin                    Application
 (via CLI)               (via AWS SDK)
```

**The magic**: Applications use familiar AWS APIs while benefiting from Vault's centralized secret management, audit trails, and rotation capabilities. 