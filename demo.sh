#!/bin/bash

# HashiCorp Vault Enterprise Secret Sync with AWS Demo
# This script demonstrates the complete secret sync workflow

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration variables
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-root}"
AWS_REGION="${AWS_REGION:-us-east-1}"
KV_MOUNT_PATH="demo-secrets"
SECRET_NAME="database"
SYNC_DESTINATION="demo-aws"

# Demo pacing - set to 0 to skip pauses
DEMO_PAUSE="${DEMO_PAUSE:-3}"

pause_demo() {
    if [ "$DEMO_PAUSE" -gt 0 ]; then
        echo -e "${CYAN}Press Enter to continue...${NC}"
        read -r
    else
        sleep 1
    fi
}

show_section() {
    echo
    echo -e "${BOLD}${BLUE}========================================${NC}"
    echo -e "${BOLD}${BLUE}  $1  ${NC}"
    echo -e "${BOLD}${BLUE}========================================${NC}"
    echo
}

show_step() {
    echo -e "${YELLOW}🔧 $1${NC}"
    echo
}

show_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

show_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

show_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

execute_command() {
    echo -e "${BLUE}Running: ${BOLD}$1${NC}"
    echo
    eval "$1"
    echo
}

# Start the demo
show_section "HashiCorp Vault Enterprise Secret Sync Demo"
echo -e "${CYAN}This demo showcases how Vault Enterprise automatically synchronizes${NC}"
echo -e "${CYAN}secrets to AWS Secrets Manager, enabling applications to use${NC}"
echo -e "${CYAN}native AWS SDKs while maintaining centralized secret management.${NC}"
echo

# Check prerequisites
show_step "Verifying Prerequisites"
export VAULT_ADDR VAULT_TOKEN

if ! vault status &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Vault. Please ensure Vault is running.${NC}"
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}❌ AWS credentials not configured. Please run 'aws configure' first.${NC}"
    exit 1
fi

# Check if .aws-credentials file exists (created by setup script)
if [ -f ".aws-credentials" ]; then
    show_info "Loading AWS credentials from setup..."
    source .aws-credentials
else
    show_warning "AWS credentials file not found. Using current AWS CLI credentials."
    AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)
    AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)
    
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        echo -e "${RED}❌ AWS credentials not found. Please run setup-demo.sh first.${NC}"
        exit 1
    fi
fi

show_success "All prerequisites satisfied"
pause_demo

# Step 1: Show current Vault secret
show_section "Step 1: Examining Our Vault Secret"
show_info "Let's start by looking at the secret we have stored in Vault's KV v2 engine."

execute_command "vault kv get $KV_MOUNT_PATH/$SECRET_NAME"

show_info "This secret contains database credentials that we'll sync to AWS Secrets Manager."
pause_demo

# Step 2: Configure Secret Sync Destination
show_section "Step 2: Configuring AWS Secrets Manager Sync Destination"
show_info "Now we'll configure Vault to sync secrets to AWS Secrets Manager."
show_info "This creates a 'destination' that defines how to connect to AWS."

execute_command "vault write sys/sync/destinations/aws-sm/$SYNC_DESTINATION \\
  access_key_id=\"$AWS_ACCESS_KEY_ID\" \\
  secret_access_key=\"$AWS_SECRET_ACCESS_KEY\" \\
  region=\"$AWS_REGION\""

show_success "AWS Secrets Manager destination configured successfully"
pause_demo

# Step 3: Create Secret Association
show_section "Step 3: Creating Secret Association"
show_info "Now we'll associate our Vault secret with the AWS destination."
show_info "This tells Vault which secrets should be synchronized and where."

execute_command "vault write sys/sync/destinations/aws-sm/$SYNC_DESTINATION/associations/set \\
  mount=\"$KV_MOUNT_PATH\" \\
  secret_name=\"$SECRET_NAME\""

show_success "Secret association created - sync should begin automatically"
show_info "Vault will now automatically create this secret in AWS Secrets Manager."
echo
show_info "Let's wait a few seconds for the initial sync to complete..."
sleep 5
pause_demo

# Step 4: Verify Secret in AWS
show_section "Step 4: Verifying Secret in AWS Secrets Manager"
show_info "Let's check that our secret has been created in AWS Secrets Manager."

echo -e "${BLUE}Listing secrets in AWS Secrets Manager:${NC}"
execute_command "aws secretsmanager list-secrets --region $AWS_REGION --query 'SecretList[?contains(Name, \`vault-kv\`)].{Name:Name,Description:Description}' --output table"

EXPECTED_SECRET_NAME="vault-kv_${KV_MOUNT_PATH}-${SECRET_NAME}"
show_info "Our secret should appear as: $EXPECTED_SECRET_NAME"
echo

echo -e "${BLUE}Retrieving the secret value from AWS:${NC}"
execute_command "aws secretsmanager get-secret-value \\
  --secret-id \"$EXPECTED_SECRET_NAME\" \\
  --region $AWS_REGION \\
  --query 'SecretString' \\
  --output text | jq ."

show_success "Secret successfully synchronized to AWS Secrets Manager!"
pause_demo

# Step 5: Demonstrate Secret Rotation
show_section "Step 5: Demonstrating Automatic Secret Rotation"
show_info "Now let's demonstrate the power of Secret Sync by updating our secret in Vault."
show_info "Watch how the change automatically propagates to AWS Secrets Manager."

# Generate new credentials
NEW_USERNAME="app-service-account-$(date +%s)"
NEW_PASSWORD=$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-25)

echo -e "${BLUE}Updating secret in Vault with new credentials:${NC}"
execute_command "vault kv put $KV_MOUNT_PATH/$SECRET_NAME \\
  username=\"$NEW_USERNAME\" \\
  password=\"$NEW_PASSWORD\" \\
  updated_by=\"vault-secret-sync-demo\" \\
  updated_at=\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""

show_info "Secret updated in Vault. Let's wait for the sync to AWS..."
sleep 8

echo -e "${BLUE}Checking the updated secret in AWS Secrets Manager:${NC}"
execute_command "aws secretsmanager get-secret-value \\
  --secret-id \"$EXPECTED_SECRET_NAME\" \\
  --region $AWS_REGION \\
  --query 'SecretString' \\
  --output text | jq ."

show_success "Secret automatically updated in AWS! This is the power of Secret Sync."
pause_demo

# Step 6: Show Sync Status
show_section "Step 6: Monitoring Sync Status"
show_info "Vault provides detailed information about sync operations."

echo -e "${BLUE}Checking sync destination status:${NC}"
execute_command "vault read sys/sync/destinations/aws-sm/$SYNC_DESTINATION"

echo -e "${BLUE}Checking association status:${NC}"
execute_command "vault read sys/sync/destinations/aws-sm/$SYNC_DESTINATION/associations/$KV_MOUNT_PATH/$SECRET_NAME"

pause_demo

# Step 7: Application Usage Example
show_section "Step 7: How Applications Would Use This"
show_info "Applications can now retrieve secrets using standard AWS SDK calls."
show_info "Here's what the application code would look like:"

cat << 'EOF'

# Python Example using boto3
import boto3
import json

def get_database_credentials():
    """Retrieve database credentials from AWS Secrets Manager"""
    client = boto3.client('secretsmanager', region_name='us-east-1')
    
    try:
        response = client.get_secret_value(
            SecretId='vault-kv_demo-secrets-database'
        )
        secret = json.loads(response['SecretString'])
        return {
            'username': secret['username'],
            'password': secret['password']
        }
    except Exception as e:
        print(f"Error retrieving secret: {e}")
        return None

# Usage
creds = get_database_credentials()
if creds:
    print(f"Connecting to database as: {creds['username']}")

EOF

show_info "The application doesn't know or care that the secret comes from Vault!"
show_info "It uses standard AWS APIs, while you get centralized management in Vault."
pause_demo

# Step 8: Key Benefits Summary
show_section "Step 8: Key Benefits of This Architecture"

echo -e "${GREEN}🎯 Centralized Secret Management${NC}"
echo -e "   • All secrets stored and managed in Vault"
echo -e "   • Single source of truth for credentials"
echo

echo -e "${GREEN}🔄 Automatic Synchronization${NC}"
echo -e "   • Changes in Vault automatically sync to AWS"
echo -e "   • No manual intervention required"
echo

echo -e "${GREEN}🛡️  Enhanced Security${NC}"
echo -e "   • Comprehensive audit trails in Vault"
echo -e "   • Consistent security policies across environments"
echo

echo -e "${GREEN}🚀 Developer Experience${NC}"
echo -e "   • Applications use familiar AWS SDKs"
echo -e "   • No changes required to existing application code"
echo

echo -e "${GREEN}🔧 Operational Benefits${NC}"
echo -e "   • Automated credential rotation capabilities"
echo -e "   • Consistent secret management across clouds"
echo

pause_demo

# Demo Complete
show_section "Demo Complete!"
echo -e "${GREEN}Congratulations! You've successfully demonstrated:${NC}"
echo -e "${GREEN}✅ Vault Secret Sync configuration${NC}"
echo -e "${GREEN}✅ Automatic secret synchronization to AWS${NC}"
echo -e "${GREEN}✅ Real-time secret updates${NC}"
echo -e "${GREEN}✅ Application integration patterns${NC}"
echo

echo -e "${YELLOW}Next Steps:${NC}"
echo -e "${BLUE}• Explore multi-cloud sync (Azure, GCP)${NC}"
echo -e "${BLUE}• Set up automated credential rotation${NC}"
echo -e "${BLUE}• Implement this in your development environment${NC}"
echo -e "${BLUE}• Review Vault Enterprise features for production${NC}"
echo

echo -e "${CYAN}When you're ready to clean up, run: ${BOLD}./cleanup-demo.sh${NC}"
echo

show_success "Thank you for exploring HashiCorp Vault Enterprise Secret Sync!" 