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

# Ensure Secret Sync is activated
show_step "Verifying Secret Sync Feature"
show_info "Checking if Secret Sync is activated on this Vault instance..."

if vault read sys/activation-flags/secrets-sync &> /dev/null; then
    show_success "Secret Sync feature is already activated"
else
    show_info "Activating Secret Sync feature..."
    if vault write -f sys/activation-flags/secrets-sync/activate &> /dev/null; then
        show_success "Secret Sync feature activated successfully"
    else
        echo -e "${RED}❌ Failed to activate Secret Sync feature${NC}"
        echo -e "${BLUE}   Please ensure you have a valid Vault Enterprise license${NC}"
        echo -e "${BLUE}   and run: vault write -f sys/activation-flags/secrets-sync/activate${NC}"
        exit 1
    fi
fi
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

# Verify the secret exists first
show_info "Verifying secret exists before creating association..."
if ! vault kv get "$KV_MOUNT_PATH/$SECRET_NAME" &> /dev/null; then
    echo -e "${RED}❌ Secret $KV_MOUNT_PATH/$SECRET_NAME does not exist${NC}"
    echo -e "${BLUE}   Creating secret first...${NC}"
    vault kv put "$KV_MOUNT_PATH/$SECRET_NAME" \
        username="temp-user" \
        password="temp-password"
fi

# Create the association using the correct path format
execute_command "vault write sys/sync/destinations/aws-sm/$SYNC_DESTINATION/associations/set \\
  mount=\"$KV_MOUNT_PATH\" \\
  secret_name=\"$SECRET_NAME\""

show_success "Secret association created - sync should begin automatically"
show_info "Vault will now automatically create this secret in AWS Secrets Manager."
echo
show_info "Let's wait for the initial sync to complete..."
sleep 10
pause_demo

# Step 4: Verify Secret in AWS
show_section "Step 4: Verifying Secret in AWS Secrets Manager"
show_info "Let's check that our secret has been created in AWS Secrets Manager."

echo -e "${BLUE}Listing secrets in AWS Secrets Manager that start with 'vault':${NC}"
execute_command "aws secretsmanager list-secrets --region $AWS_REGION --output json | jq '.SecretList[] | select(.Name | startswith(\"vault\")) | {Name: .Name, Description: .Description}'"

# Get the mount accessor to build the correct secret name
MOUNT_ACCESSOR=$(vault read -format=json sys/sync/destinations/aws-sm/$SYNC_DESTINATION/associations | jq -r '.data.associated_secrets | to_entries[0].value.accessor')
AWS_SECRET_NAME="vault/${MOUNT_ACCESSOR}/${SECRET_NAME}"

show_info "Based on Vault's mount accessor, the secret in AWS should be named: $AWS_SECRET_NAME"
echo

echo -e "${BLUE}Retrieving the secret value from AWS:${NC}"
execute_command "aws secretsmanager get-secret-value \\
  --secret-id \"$AWS_SECRET_NAME\" \\
  --region $AWS_REGION \\
  --query 'SecretString' \\
  --output text | jq ."

show_success "Secret successfully synchronized to AWS Secrets Manager!"
pause_demo

# Step 5: Demonstrate Secret Rotation
show_section "Step 5: Demonstrating Interactive Secret Updates"
show_info "Now let's demonstrate the power of Secret Sync by updating our secret in Vault."
show_info "You'll choose a new username, and we'll watch how the change automatically propagates to AWS."

# Get current secret values first
echo -e "${BLUE}First, let's see the current secret values:${NC}"
execute_command "vault kv get -format=json $KV_MOUNT_PATH/$SECRET_NAME | jq -r '.data.data'"

# Get current values for preservation
CURRENT_SECRET=$(vault kv get -format=json "$KV_MOUNT_PATH/$SECRET_NAME" | jq -r '.data.data')
CURRENT_PASSWORD=$(echo "$CURRENT_SECRET" | jq -r '.password')

echo
show_info "We'll keep the current password but update the username."
echo -e "${YELLOW}Current username: $(echo "$CURRENT_SECRET" | jq -r '.username')${NC}"
echo

# Prompt for new username
echo -e "${CYAN}Please enter a new username for the database credentials:${NC}"
read -p "New username: " NEW_USERNAME

# Validate input
if [ -z "$NEW_USERNAME" ]; then
    echo -e "${YELLOW}No username provided. Using default: app-service-account-$(date +%s)${NC}"
    NEW_USERNAME="app-service-account-$(date +%s)"
fi

echo
echo -e "${BLUE}Updating secret in Vault with your new username: $NEW_USERNAME${NC}"
execute_command "vault kv put $KV_MOUNT_PATH/$SECRET_NAME \\
  username=\"$NEW_USERNAME\" \\
  password=\"$CURRENT_PASSWORD\" \\
  updated_by=\"vault-secret-sync-demo\" \\
  updated_at=\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""

show_info "Secret updated in Vault. Let's wait for the sync to AWS..."
sleep 8

echo -e "${BLUE}Checking the updated secret in AWS Secrets Manager:${NC}"
execute_command "aws secretsmanager get-secret-value \\
  --secret-id \"$AWS_SECRET_NAME\" \\
  --region $AWS_REGION \\
  --query 'SecretString' \\
  --output text | jq ."

show_success "Secret automatically updated in AWS with your chosen username!"
show_info "Notice how only the username changed while the password remained the same."
pause_demo

# Step 6: Show Sync Status
show_section "Step 6: Monitoring Sync Status"
show_info "Vault provides detailed information about sync operations."

echo -e "${BLUE}Checking sync destination status:${NC}"
execute_command "vault read sys/sync/destinations/aws-sm/$SYNC_DESTINATION"

echo -e "${BLUE}Checking all associations for this destination:${NC}"
execute_command "vault read sys/sync/destinations/aws-sm/$SYNC_DESTINATION/associations"

pause_demo

# Step 7: Key Benefits Summary
show_section "Step 7: Key Benefits of This Architecture"

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