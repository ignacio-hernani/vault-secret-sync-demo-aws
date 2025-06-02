# Troubleshooting Guide

This guide helps resolve common issues encountered during the HashiCorp Vault Enterprise Secret Sync demo.

## Prerequisites Issues

### Vault CLI Not Found
```
❌ Vault CLI is not installed. Please install it first.
```

**Solution**: Install the Vault CLI:
- **macOS**: `brew install vault`
- **Linux**: Download from [HashiCorp releases](https://releases.hashicorp.com/vault/)
- **Windows**: Use chocolatey: `choco install vault`

### AWS CLI Not Found
```
❌ AWS CLI is not installed. Please install it first.
```

**Solution**: Install the AWS CLI:
- **macOS**: `brew install awscli`
- **Linux/Windows**: Follow [AWS CLI installation guide](https://aws.amazon.com/cli/)

### Docker Not Running
```
❌ Docker is not running. Please start Docker Desktop.
```

**Solution**: Start Docker Desktop and ensure it's running:
```bash
# Check Docker status
docker info
```

## Vault Connection Issues

### Cannot Connect to Vault
```
❌ Cannot connect to Vault at http://127.0.0.1:8200
```

**Solutions**:
1. Start Vault Enterprise:
   ```bash
   ./vault.sh
   ```

2. Check if Vault is running:
   ```bash
   docker ps | grep vault
   ```

3. Verify Vault environment variables:
   ```bash
   echo $VAULT_ADDR
   echo $VAULT_TOKEN
   ```

4. If using a different Vault address, update:
   ```bash
   export VAULT_ADDR="your-vault-address"
   export VAULT_TOKEN="your-vault-token"
   ```

### Vault Enterprise License Issues
```
❌ Vault Enterprise license not detected.
```

**Solutions**:
1. Ensure `vault.hclic` file exists in the project directory
2. Restart Vault with the license:
   ```bash
   docker stop vault-enterprise
   ./vault.sh
   ```

3. Verify license status:
   ```bash
   vault read sys/license/status
   ```

### Secret Sync Feature Not Activated
```
❌ the Secrets Sync feature is not activated on this Vault instance
```

**Solutions**:
1. Activate the Secret Sync feature:
   ```bash
   vault write -f sys/activation-flags/secrets-sync/activate
   ```

2. Verify activation was successful:
   ```bash
   vault read sys/activation-flags/secrets-sync
   ```

3. Check if your license supports Secret Sync:
   ```bash
   vault read sys/license/status
   ```

**Note**: Secret Sync activation may impact your Vault Enterprise license usage. This is a normal requirement for Vault 1.16+.

## AWS Credential Issues

### AWS Credentials Not Configured
```
❌ AWS credentials not configured.
```

**Solutions**:
1. Configure AWS CLI:
   ```bash
   aws configure
   ```

2. Or set environment variables:
   ```bash
   export AWS_ACCESS_KEY_ID="your-access-key"
   export AWS_SECRET_ACCESS_KEY="your-secret-key"
   export AWS_DEFAULT_REGION="us-east-1"
   ```

3. Verify credentials:
   ```bash
   aws sts get-caller-identity
   ```

### Permission Denied Errors
```
❌ User: arn:aws:iam::123456789012:user/vault-secret-sync is not authorized to perform: secretsmanager:CreateSecret
```

**Solutions**:
1. Verify IAM policy is attached:
   ```bash
   aws iam list-attached-user-policies --user-name vault-secret-sync
   ```

2. Check policy document:
   ```bash
   aws iam get-policy-version --policy-arn arn:aws:iam::ACCOUNT:policy/VaultSecretSyncPolicy --version-id v1
   ```

3. Re-run setup if policy is missing:
   ```bash
   ./setup-demo.sh
   ```

## Secret Sync Issues

### Secret Not Appearing in AWS
**Symptoms**: Vault shows sync configured but secret doesn't appear in AWS Secrets Manager.

**Solutions**:
1. Wait longer (sync can take 30-60 seconds initially)
2. Check sync status:
   ```bash
   vault read sys/sync/destinations/aws-sm/demo-aws
   ```

3. Check association status:
   ```bash
   vault read sys/sync/destinations/aws-sm/demo-aws/associations/demo-secrets/database
   ```

4. Look for errors in Vault logs:
   ```bash
   docker logs vault-enterprise | grep -i sync
   ```

5. **Debug step-by-step**:
   ```bash
   # Check if destination exists
   vault list sys/sync/destinations/aws-sm/
   
   # Check if associations exist
   vault list sys/sync/destinations/aws-sm/demo-aws/associations/
   
   # Test AWS connectivity
   aws secretsmanager list-secrets --region us-east-1 --max-results 1
   
   # Check for the secret in AWS (may take several minutes)
   aws secretsmanager describe-secret --secret-id "vault/kv_ACCESSOR/database"
   
   # Replace kv_ACCESSOR with your actual mount accessor from:
   vault read sys/sync/destinations/aws-sm/demo-aws/associations
   ```

6. **Common timing issues**:
   - Initial sync: 30-60 seconds
   - Complex secrets: Up to 2-3 minutes
   - Network issues: Can cause longer delays

### Secret Updates Not Syncing
**Symptoms**: Changes to secrets in Vault don't reflect in AWS.

**Solutions**:
1. Verify the secret was updated in Vault:
   ```bash
   vault kv get demo-secrets/database
   ```

2. Check if association is still active:
   ```bash
   vault list sys/sync/destinations/aws-sm/demo-aws/associations
   ```

3. Recreate association if necessary:
   ```bash
   vault write sys/sync/destinations/aws-sm/demo-aws/associations/remove \
     mount="demo-secrets" \
     secret_name="database"
   
   vault write sys/sync/destinations/aws-sm/demo-aws/associations/set \
     mount="demo-secrets" \
     secret_name="database"
   ```

### Access Denied in AWS
```
❌ AccessDenied: User is not authorized to perform secretsmanager operations
```

**Solutions**:
1. Verify the IAM user exists:
   ```bash
   aws iam get-user --user-name vault-secret-sync
   ```

2. Check if policy is properly attached:
   ```bash
   aws iam list-attached-user-policies --user-name vault-secret-sync
   ```

3. Verify AWS credentials are for the correct account:
   ```bash
   aws sts get-caller-identity
   ```

## Performance Issues

### Slow Secret Sync
**Symptoms**: Secrets take a very long time to sync.

**Solutions**:
1. This is normal for initial sync (can take 30-60 seconds)
2. Subsequent updates should be faster (5-15 seconds)
3. Check Vault server resources if consistently slow

## Cleanup Issues

### Resources Not Deleted
**Symptoms**: Cleanup script reports errors or resources remain.

**Solutions**:
1. Run cleanup with verbose output:
   ```bash
   bash -x ./cleanup-demo.sh
   ```

2. Manually clean specific resources:
   ```bash
   # Remove Vault associations
   vault write sys/sync/destinations/aws-sm/demo-aws/associations/remove \
     mount="demo-secrets" secret_name="database"
   
   # Remove AWS secrets
   aws secretsmanager delete-secret \
     --secret-id "vault-kv_demo-secrets-database" \
     --force-delete-without-recovery
   
   # Remove IAM user
   aws iam delete-user --user-name vault-secret-sync
   ```

3. Check for dependent resources:
   ```bash
   # List remaining access keys
   aws iam list-access-keys --user-name vault-secret-sync
   
   # List attached policies
   aws iam list-attached-user-policies --user-name vault-secret-sync
   ```

## Demo Script Issues

### jq Command Not Found
```
❌ jq: command not found
```

**Solution**: Install jq JSON processor:
- **macOS**: `brew install jq`
- **Linux**: `sudo apt-get install jq` or `sudo yum install jq`
- **Windows**: Download from [jq website](https://stedolan.github.io/jq/)

### Script Permissions
```
❌ Permission denied: ./setup-demo.sh
```

**Solution**: Make scripts executable:
```bash
chmod +x setup-demo.sh demo.sh cleanup-demo.sh
```

## Advanced Troubleshooting

### Enable Debug Logging
To get more detailed information about what's happening:

1. **Vault Debug Logs**:
   ```bash
   # Check current log level
   docker logs vault-enterprise | tail -20
   
   # Restart with debug logging
   docker stop vault-enterprise
   # Edit vault.sh to set VAULT_LOG_LEVEL=debug
   ./vault.sh
   ```

2. **AWS CLI Debug**:
   ```bash
   # Add --debug flag to AWS commands
   aws --debug secretsmanager list-secrets
   ```

### Manual Verification Steps
If automated scripts fail, try these manual verification steps:

1. **Test Vault Connectivity**:
   ```bash
   curl -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/sys/health"
   ```

2. **Test AWS Connectivity**:
   ```bash
   aws secretsmanager list-secrets --region us-east-1 --max-results 1
   ```

3. **Verify Secret Sync Configuration**:
   ```bash
   vault read -format=json sys/sync/destinations/aws-sm/demo-aws
   ```

## Getting Help

If you continue experiencing issues:

1. **Check Vault Documentation**: [Vault Secret Sync Documentation](https://developer.hashicorp.com/vault/docs/sync)
2. **HashiCorp Community Forum**: [HashiCorp Discuss](https://discuss.hashicorp.com/c/vault)
3. **GitHub Issues**: Report issues with this demo on the project repository

## Environment Reset

If all else fails, perform a complete environment reset:

```bash
# Stop all containers
docker stop vault-enterprise

# Clean up all demo resources
./cleanup-demo.sh

# Remove Docker containers and images
docker system prune -f

# Restart from scratch
./vault.sh
./setup-demo.sh
``` 