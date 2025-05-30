#!/bin/bash

# HashiCorp Vault Enterprise Secret Sync on AWS Demo Setup Script
# This script automates the setup process described in the README

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

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Vault Enterprise Secret Sync Setup  ${NC}"
echo -e "${BLUE}========================================${NC}"
echo

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

# Check if Vault CLI is installed
if ! command -v vault &> /dev/null; then
    echo -e "${RED}❌ Vault CLI is not installed. Please install it first.${NC}"
    echo -e "${BLUE}   Download from: https://developer.hashicorp.com/vault/docs/install${NC}"
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI is not installed. Please install it first.${NC}"
    echo -e "${BLUE}   Download from: https://aws.amazon.com/cli/${NC}"
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo -e "${RED}❌ Docker is not running. Please start Docker Desktop.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All prerequisites are satisfied.${NC}"
echo

# Check Vault connectivity
echo -e "${YELLOW}Verifying Vault connectivity...${NC}"
export VAULT_ADDR VAULT_TOKEN

if ! vault status &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Vault at $VAULT_ADDR${NC}"
    echo -e "${BLUE}   Please ensure Vault is running: ./vault.sh${NC}"
    exit 1
fi

# Check if this is Vault Enterprise
if ! vault read sys/license/status &> /dev/null; then
    echo -e "${RED}❌ Vault Enterprise license not detected.${NC}"
    echo -e "${BLUE}   Please ensure you have a valid vault.hclic file and restart Vault.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Vault Enterprise is running and accessible.${NC}"
echo

# Check AWS credentials
echo -e "${YELLOW}Verifying AWS credentials...${NC}"
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ AWS credentials not configured.${NC}"
    echo -e "${BLUE}   Please configure AWS CLI: aws configure${NC}"
    exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}✅ AWS credentials configured for account: $AWS_ACCOUNT_ID${NC}"
echo

# Set up AWS IAM resources
echo -e "${YELLOW}Setting up AWS IAM resources...${NC}"

# Check if policy already exists
if aws iam get-policy --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$IAM_POLICY_NAME" &> /dev/null; then
    echo -e "${YELLOW}⚠️  IAM policy $IAM_POLICY_NAME already exists. Skipping creation.${NC}"
else
    echo -e "${BLUE}Creating IAM policy: $IAM_POLICY_NAME${NC}"
    aws iam create-policy \
        --policy-name "$IAM_POLICY_NAME" \
        --policy-document file://aws-policy.json \
        --description "Policy for HashiCorp Vault Secret Sync to AWS Secrets Manager"
    echo -e "${GREEN}✅ IAM policy created successfully.${NC}"
fi

# Check if user already exists
if aws iam get-user --user-name "$IAM_USER_NAME" &> /dev/null; then
    echo -e "${YELLOW}⚠️  IAM user $IAM_USER_NAME already exists.${NC}"
    
    # Check if policy is attached
    if aws iam list-attached-user-policies --user-name "$IAM_USER_NAME" --query 'AttachedPolicies[?PolicyName==`'$IAM_POLICY_NAME'`]' --output text | grep -q "$IAM_POLICY_NAME"; then
        echo -e "${YELLOW}⚠️  Policy already attached to user.${NC}"
    else
        echo -e "${BLUE}Attaching policy to existing user...${NC}"
        aws iam attach-user-policy \
            --user-name "$IAM_USER_NAME" \
            --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$IAM_POLICY_NAME"
        echo -e "${GREEN}✅ Policy attached to user.${NC}"
    fi
else
    echo -e "${BLUE}Creating IAM user: $IAM_USER_NAME${NC}"
    aws iam create-user --user-name "$IAM_USER_NAME"
    
    echo -e "${BLUE}Attaching policy to user...${NC}"
    aws iam attach-user-policy \
        --user-name "$IAM_USER_NAME" \
        --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$IAM_POLICY_NAME"
    echo -e "${GREEN}✅ IAM user created and policy attached.${NC}"
fi

# Create access keys if they don't exist
ACCESS_KEY_COUNT=$(aws iam list-access-keys --user-name "$IAM_USER_NAME" --query 'AccessKeyMetadata | length(@)')
if [ "$ACCESS_KEY_COUNT" -eq 0 ]; then
    echo -e "${BLUE}Creating access keys for IAM user...${NC}"
    ACCESS_KEY_OUTPUT=$(aws iam create-access-key --user-name "$IAM_USER_NAME")
    AWS_ACCESS_KEY_ID=$(echo "$ACCESS_KEY_OUTPUT" | jq -r '.AccessKey.AccessKeyId')
    AWS_SECRET_ACCESS_KEY=$(echo "$ACCESS_KEY_OUTPUT" | jq -r '.AccessKey.SecretAccessKey')
    
    # Store credentials in a file for later use
    cat > .aws-credentials << EOF
# AWS credentials for Vault Secret Sync
# Use these credentials when configuring the Vault sync destination
export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
export AWS_REGION="$AWS_REGION"
EOF

    echo -e "${GREEN}✅ Access keys created and saved to .aws-credentials${NC}"
    echo -e "${YELLOW}📝 Important: Save these credentials securely!${NC}"
    echo -e "${BLUE}   Access Key ID: $AWS_ACCESS_KEY_ID${NC}"
    echo -e "${BLUE}   Secret Access Key: [HIDDEN - see .aws-credentials file]${NC}"
else
    echo -e "${YELLOW}⚠️  Access keys already exist for user $IAM_USER_NAME${NC}"
    echo -e "${BLUE}   If you need new keys, delete existing ones first or use the existing credentials.${NC}"
fi

echo

# Configure Vault
echo -e "${YELLOW}Configuring Vault...${NC}"

# Enable KV v2 secret engine
if vault secrets list | grep -q "^$KV_MOUNT_PATH/"; then
    echo -e "${YELLOW}⚠️  KV v2 secret engine already enabled at $KV_MOUNT_PATH${NC}"
else
    echo -e "${BLUE}Enabling KV v2 secret engine at $KV_MOUNT_PATH...${NC}"
    vault secrets enable -path="$KV_MOUNT_PATH" kv-v2
    echo -e "${GREEN}✅ KV v2 secret engine enabled.${NC}"
fi

# Create a sample secret
echo -e "${BLUE}Creating sample database secret...${NC}"
SAMPLE_USERNAME="app-service-account-$(date +%s)"
SAMPLE_PASSWORD=$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-25)

vault kv put "$KV_MOUNT_PATH/$SECRET_NAME" \
    username="$SAMPLE_USERNAME" \
    password="$SAMPLE_PASSWORD" \
    created_by="vault-secret-sync-demo" \
    created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo -e "${GREEN}✅ Sample secret created at $KV_MOUNT_PATH/$SECRET_NAME${NC}"
echo

# Display next steps
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}           Setup Complete!             ${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo -e "${GREEN}✅ AWS IAM user and policy configured${NC}"
echo -e "${GREEN}✅ Vault KV v2 secret engine enabled${NC}"
echo -e "${GREEN}✅ Sample secret created${NC}"
echo
echo -e "${YELLOW}Next steps:${NC}"
echo -e "${BLUE}1. Review the AWS credentials in .aws-credentials${NC}"
echo -e "${BLUE}2. Run the demo: ./demo.sh${NC}"
echo -e "${BLUE}3. When finished, clean up: ./cleanup-demo.sh${NC}"
echo
echo -e "${YELLOW}Manual configuration option:${NC}"
echo -e "${BLUE}If you prefer to configure the sync destination manually, use:${NC}"
echo -e "${BLUE}  vault write sys/sync/destinations/aws-sm/demo-aws \\${NC}"
echo -e "${BLUE}    access_key_id=\"<your-access-key>\" \\${NC}"
echo -e "${BLUE}    secret_access_key=\"<your-secret-key>\" \\${NC}"
echo -e "${BLUE}    region=\"$AWS_REGION\"${NC}"
echo
