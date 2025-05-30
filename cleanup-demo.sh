#!/bin/bash

# HashiCorp Vault Enterprise Secret Sync AWS Demo Cleanup Script
# This script removes all resources created during the demo

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-root}"
AWS_REGION="${AWS_REGION:-us-east-1}"
IAM_USER_NAME="vault-secret-sync"
IAM_POLICY_NAME="VaultSecretSyncPolicy"
KV_MOUNT_PATH="demo-secrets"
SECRET_NAME="database"
SYNC_DESTINATION="demo-aws"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Vault Enterprise Demo Cleanup        ${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Confirmation prompt
echo -e "${YELLOW}⚠️  This will remove ALL demo resources from:${NC}"
echo -e "${BLUE}   • Vault secret sync configurations${NC}"
echo -e "${BLUE}   • Vault KV v2 secrets${NC}"
echo -e "${BLUE}   • AWS Secrets Manager secrets${NC}"
echo -e "${BLUE}   • AWS IAM user and policy${NC}"
echo
echo -e "${RED}This action cannot be undone!${NC}"
echo -n "Are you sure you want to continue? (yes/no): "
read -r confirmation

if [ "$confirmation" != "yes" ]; then
    echo -e "${YELLOW}Cleanup cancelled.${NC}"
    exit 0
fi

echo

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"
export VAULT_ADDR VAULT_TOKEN

if ! vault status &> /dev/null; then
    echo -e "${YELLOW}⚠️  Cannot connect to Vault. Skipping Vault cleanup.${NC}"
    SKIP_VAULT=true
else
    echo -e "${GREEN}✅ Vault is accessible${NC}"
    SKIP_VAULT=false
fi

if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${YELLOW}⚠️  AWS credentials not configured. Skipping AWS cleanup.${NC}"
    SKIP_AWS=true
else
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo -e "${GREEN}✅ AWS credentials configured for account: $AWS_ACCOUNT_ID${NC}"
    SKIP_AWS=false
fi

echo

# Cleanup Vault Secret Sync Associations
if [ "$SKIP_VAULT" = false ]; then
    echo -e "${YELLOW}Cleaning up Vault Secret Sync...${NC}"
    
    # Remove secret association
    if vault read "sys/sync/destinations/aws-sm/$SYNC_DESTINATION/associations/$KV_MOUNT_PATH/$SECRET_NAME" &> /dev/null; then
        echo -e "${BLUE}Removing secret association...${NC}"
        vault write "sys/sync/destinations/aws-sm/$SYNC_DESTINATION/associations/remove" \
            mount="$KV_MOUNT_PATH" \
            secret_name="$SECRET_NAME"
        echo -e "${GREEN}✅ Secret association removed${NC}"
    else
        echo -e "${YELLOW}⚠️  Secret association not found or already removed${NC}"
    fi
    
    # Remove sync destination
    if vault read "sys/sync/destinations/aws-sm/$SYNC_DESTINATION" &> /dev/null; then
        echo -e "${BLUE}Removing sync destination...${NC}"
        vault delete "sys/sync/destinations/aws-sm/$SYNC_DESTINATION"
        echo -e "${GREEN}✅ Sync destination removed${NC}"
    else
        echo -e "${YELLOW}⚠️  Sync destination not found or already removed${NC}"
    fi
    
    # Optional: Remove the KV secret
    echo -n "Do you want to remove the KV secret as well? (yes/no): "
    read -r remove_secret
    if [ "$remove_secret" = "yes" ]; then
        if vault kv get "$KV_MOUNT_PATH/$SECRET_NAME" &> /dev/null; then
            echo -e "${BLUE}Removing Vault secret...${NC}"
            vault kv delete "$KV_MOUNT_PATH/$SECRET_NAME"
            echo -e "${GREEN}✅ Vault secret removed${NC}"
        else
            echo -e "${YELLOW}⚠️  Vault secret not found or already removed${NC}"
        fi
    fi
    
    # Optional: Disable the KV engine
    echo -n "Do you want to disable the KV v2 secret engine? (yes/no): "
    read -r disable_kv
    if [ "$disable_kv" = "yes" ]; then
        if vault secrets list | grep -q "^$KV_MOUNT_PATH/"; then
            echo -e "${BLUE}Disabling KV v2 secret engine...${NC}"
            vault secrets disable "$KV_MOUNT_PATH"
            echo -e "${GREEN}✅ KV v2 secret engine disabled${NC}"
        else
            echo -e "${YELLOW}⚠️  KV v2 secret engine not found or already disabled${NC}"
        fi
    fi
    
    echo
fi

# Cleanup AWS Resources
if [ "$SKIP_AWS" = false ]; then
    echo -e "${YELLOW}Cleaning up AWS resources...${NC}"
    
    # Find and remove synced secrets from AWS Secrets Manager
    echo -e "${BLUE}Searching for synced secrets in AWS Secrets Manager...${NC}"
    VAULT_SECRETS=$(aws secretsmanager list-secrets --region "$AWS_REGION" --query 'SecretList[?contains(Name, `vault-kv`)].Name' --output text)
    
    if [ -n "$VAULT_SECRETS" ]; then
        echo -e "${BLUE}Found the following Vault-synced secrets:${NC}"
        echo "$VAULT_SECRETS"
        echo
        
        for secret in $VAULT_SECRETS; do
            echo -e "${BLUE}Deleting secret: $secret${NC}"
            aws secretsmanager delete-secret \
                --secret-id "$secret" \
                --region "$AWS_REGION" \
                --force-delete-without-recovery &> /dev/null || true
            echo -e "${GREEN}✅ Secret $secret deleted${NC}"
        done
    else
        echo -e "${YELLOW}⚠️  No Vault-synced secrets found in AWS Secrets Manager${NC}"
    fi
    
    # Remove IAM access keys
    if aws iam get-user --user-name "$IAM_USER_NAME" &> /dev/null; then
        echo -e "${BLUE}Removing IAM access keys...${NC}"
        ACCESS_KEYS=$(aws iam list-access-keys --user-name "$IAM_USER_NAME" --query 'AccessKeyMetadata[].AccessKeyId' --output text)
        
        for key in $ACCESS_KEYS; do
            aws iam delete-access-key --user-name "$IAM_USER_NAME" --access-key-id "$key"
            echo -e "${GREEN}✅ Access key $key deleted${NC}"
        done
    fi
    
    # Remove IAM policy from user
    if aws iam get-user --user-name "$IAM_USER_NAME" &> /dev/null; then
        echo -e "${BLUE}Detaching IAM policy from user...${NC}"
        aws iam detach-user-policy \
            --user-name "$IAM_USER_NAME" \
            --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$IAM_POLICY_NAME" &> /dev/null || true
        echo -e "${GREEN}✅ Policy detached from user${NC}"
    fi
    
    # Remove IAM user
    if aws iam get-user --user-name "$IAM_USER_NAME" &> /dev/null; then
        echo -e "${BLUE}Deleting IAM user...${NC}"
        aws iam delete-user --user-name "$IAM_USER_NAME"
        echo -e "${GREEN}✅ IAM user deleted${NC}"
    else
        echo -e "${YELLOW}⚠️  IAM user not found or already deleted${NC}"
    fi
    
    # Remove IAM policy
    if aws iam get-policy --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$IAM_POLICY_NAME" &> /dev/null; then
        echo -e "${BLUE}Deleting IAM policy...${NC}"
        aws iam delete-policy --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$IAM_POLICY_NAME"
        echo -e "${GREEN}✅ IAM policy deleted${NC}"
    else
        echo -e "${YELLOW}⚠️  IAM policy not found or already deleted${NC}"
    fi
    
    echo
fi

# Cleanup local files
echo -e "${YELLOW}Cleaning up local files...${NC}"

if [ -f ".aws-credentials" ]; then
    echo -e "${BLUE}Removing local AWS credentials file...${NC}"
    rm .aws-credentials
    echo -e "${GREEN}✅ AWS credentials file removed${NC}"
else
    echo -e "${YELLOW}⚠️  AWS credentials file not found${NC}"
fi

echo

# Final summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}           Cleanup Complete!            ${NC}"
echo -e "${BLUE}========================================${NC}"
echo

if [ "$SKIP_VAULT" = false ]; then
    echo -e "${GREEN}✅ Vault secret sync configurations removed${NC}"
    if [ "$remove_secret" = "yes" ]; then
        echo -e "${GREEN}✅ Vault secrets removed${NC}"
    fi
    if [ "$disable_kv" = "yes" ]; then
        echo -e "${GREEN}✅ Vault KV v2 engine disabled${NC}"
    fi
fi

if [ "$SKIP_AWS" = false ]; then
    echo -e "${GREEN}✅ AWS Secrets Manager secrets removed${NC}"
    echo -e "${GREEN}✅ AWS IAM user and policy removed${NC}"
fi

echo -e "${GREEN}✅ Local credential files removed${NC}"
echo

echo -e "${YELLOW}Next steps:${NC}"
echo -e "${BLUE}• Your Vault Enterprise instance is still running${NC}"
echo -e "${BLUE}• To stop Vault: docker stop vault-enterprise${NC}"
echo -e "${BLUE}• To restart the demo: ./setup-demo.sh${NC}"
echo

echo -e "${GREEN}Thank you for exploring HashiCorp Vault Enterprise Secret Sync!${NC}"
