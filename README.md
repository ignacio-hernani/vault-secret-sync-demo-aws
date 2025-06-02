# HashiCorp Vault Enterprise Secret Sync with AWS Demo

This demo showcases HashiCorp Vault Enterprise's Secret Sync capability, demonstrating how to automatically synchronize secrets stored in Vault with AWS Secrets Manager. This eliminates the need for applications to directly integrate with Vault while maintaining centralized secret management, audit trails, and automated rotation.

## What is Secret Sync?

Vault's Secret Sync feature manages the complete lifecycle of secrets by automatically synchronizing them to external providers like AWS Secrets Manager. Your applications continue using their native cloud provider integrations while benefiting from Vault's centralized secret management, comprehensive audit logging, and automated credential rotation capabilities.

## Architecture Overview

```
┌─────────────────┐    Secret Sync    ┌──────────────────────┐
│  HashiCorp      │ ───────────────── │   AWS Secrets        │
│  Vault          │                   │   Manager            │
│  (KV v2 Store)  │                   │                      │
└─────────────────┘                   └──────────────────────┘
         │                                        │
         │ Direct API                             │ Native SDK
         │ (Admin/Ops)                            │ (Applications)
         ▼                                        ▼
┌─────────────────┐                   ┌──────────────────────┐
│   Vault CLI     │                   │    Your AWS          │
│   Web UI        │                   │    Applications      │
└─────────────────┘                   └──────────────────────┘
```

## Prerequisites

Before starting this demo, ensure you have:

### Required Software
- [HashiCorp Vault CLI](https://developer.hashicorp.com/vault/docs/install) installed
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) running
- [AWS CLI](https://aws.amazon.com/cli/) installed and configured
- A valid HashiCorp Vault Enterprise license file (`vault.hclic`)

### AWS Requirements
- An AWS account with administrative permissions
- AWS CLI configured with programmatic access credentials
- Permissions to create IAM users, policies, and Secrets Manager secrets

### Environment Setup
Your Vault Enterprise instance should already be running from the provided `vault.sh` script. If not, start it:

```bash
./vault.sh
```

## Core Concepts Demonstrated

This demo illustrates several key Vault Enterprise capabilities:

1. **Centralized Secret Management**: Store and manage secrets in Vault's KV v2 secret engine
2. **Automated Synchronization**: Configure automatic sync to AWS Secrets Manager
3. **Lifecycle Management**: Demonstrate secret creation, updates, and deletion
4. **Zero-Trust Architecture**: Applications access secrets through AWS native APIs while Vault maintains control

## Quick Start

For an automated experience, use our provided scripts:

```bash
# 1. Set up the demo environment
./setup-demo.sh

# 2. Run the complete demo workflow
./demo.sh

# 3. Clean up all resources when finished
./cleanup-demo.sh
```

## Manual Step-by-Step Guide

### Step 1: Verify Vault Enterprise Setup

Confirm your Vault instance is running and accessible:

```bash
# Check Vault status
vault status

# Verify enterprise features are available
vault read sys/license/status

# Activate Secret Sync feature (required for Vault 1.16+)
vault write -f sys/activation-flags/secrets-sync/activate
```

**Important**: Secret Sync must be explicitly activated on Vault Enterprise instances. This command enables the feature but may impact your license usage.

### Step 2: AWS IAM Configuration

Create dedicated IAM credentials for Vault's Secret Sync:

```bash
# Create IAM policy for Secret Sync
aws iam create-policy \
  --policy-name VaultSecretSyncPolicy \
  --policy-document file://aws-policy.json

# Create IAM user for Vault
aws iam create-user --user-name vault-secret-sync

# Attach policy to user
aws iam attach-user-policy \
  --user-name vault-secret-sync \
  --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/VaultSecretSyncPolicy

# Create access keys
aws iam create-access-key --user-name vault-secret-sync
```

### Step 3: Configure Vault Secret Engine

Enable and configure the KV v2 secret engine:

```bash
# Enable KV v2 secret engine
vault secrets enable -path=demo-secrets kv-v2

# Create a sample database credential secret
vault kv put demo-secrets/database \
  username="app-service-account" \
  password="$(openssl rand -base64 32)"
```

### Step 4: Configure Secret Sync Destination

Set up the AWS Secrets Manager sync destination:

```bash
# Configure AWS destination with your credentials
vault write sys/sync/destinations/aws-sm/demo-aws \
  access_key_id="YOUR_ACCESS_KEY_ID" \
  secret_access_key="YOUR_SECRET_ACCESS_KEY" \
  region="us-east-1"
```

### Step 5: Create Secret Association

Associate your Vault secret with the AWS destination:

```bash
# Create the sync association
vault write sys/sync/destinations/aws-sm/demo-aws/associations/set \
  mount="demo-secrets" \
  secret_name="database"
```

### Step 6: Verify Synchronization

Check that your secret appears in AWS Secrets Manager:

```bash
# List secrets in AWS Secrets Manager
aws secretsmanager list-secrets --region us-east-1 --query 'SecretList[?starts_with(Name, `vault`)]'

# The secret will be named like: vault/kv_ACCESSOR/database 
# where kv_ACCESSOR is the mount accessor (e.g., kv_e5d814f5)

# Retrieve the synced secret value (replace kv_ACCESSOR with actual accessor)
aws secretsmanager get-secret-value --secret-id "vault/kv_ACCESSOR/database" --region us-east-1
```

### Step 7: Demonstrate Secret Rotation

Update the secret in Vault and observe automatic sync:

```bash
# Rotate the database password
vault kv put demo-secrets/database \
  username="app-service-account" \
  password="$(openssl rand -base64 32)"

# Wait a few seconds, then verify the update in AWS
aws secretsmanager get-secret-value \
  --secret-id "vault-kv_demo-secrets-database" \
  --region us-east-1
```

## Demo Scripts Explained

- **`setup-demo.sh`**: Automates AWS IAM setup and Vault configuration
- **`demo.sh`**: Runs the complete demo workflow with explanatory output
- **`cleanup-demo.sh`**: Removes all demo resources from both Vault and AWS

## Troubleshooting

Common issues and solutions are documented in [TROUBLESHOOTING.md](./TROUBLESHOOTING.md).

## Security Considerations

This demo uses simplified configurations for educational purposes. For production deployments:

- Use IAM roles instead of long-lived access keys
- Implement least-privilege access policies
- Enable comprehensive audit logging
- Use Vault's authentication methods instead of root tokens
- Deploy Vault in high-availability mode with proper TLS

## Next Steps

After completing this demo, explore:

- [Multi-cloud secret sync](https://developer.hashicorp.com/vault/docs/sync) with Azure and GCP
- [Dynamic secrets](https://developer.hashicorp.com/vault/docs/secrets/aws) for AWS
- [Vault Agent](https://developer.hashicorp.com/vault/docs/agent) for application integration
- [Vault Enterprise namespaces](https://developer.hashicorp.com/vault/docs/enterprise/namespaces) for multi-tenancy

## Resources

- [Vault Secret Sync Documentation](https://developer.hashicorp.com/vault/docs/sync)
- [AWS Secrets Manager Integration](https://developer.hashicorp.com/vault/docs/sync/awssm)
- [Vault Enterprise Features](https://developer.hashicorp.com/vault/docs/enterprise)