#!/bin/bash
# ==============================================================================
# DataSync Client Setup Script
# ==============================================================================
# Purpose: Interactive wizard to set up DataSync simulator for a new client
# Usage: ./setup-client.sh [CLIENT_NAME]
# ==============================================================================

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_DIR="$SCRIPT_DIR"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "================================================================================"
    echo "$1"
    echo "================================================================================"
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

prompt_input() {
    local prompt="$1"
    local default="$2"
    local result

    if [ -n "$default" ]; then
        read -p "$(echo -e ${CYAN}${prompt}${NC} [${default}]: )" result
        echo "${result:-$default}"
    else
        read -p "$(echo -e ${CYAN}${prompt}${NC}: )" result
        echo "$result"
    fi
}

prompt_yes_no() {
    local prompt="$1"
    local default="$2"
    local result

    if [ "$default" = "y" ]; then
        read -p "$(echo -e ${CYAN}${prompt}${NC} [Y/n]: )" result
        result="${result:-y}"
    else
        read -p "$(echo -e ${CYAN}${prompt}${NC} [y/N]: )" result
        result="${result:-n}"
    fi

    [[ "$result" =~ ^[Yy] ]]
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "Required command not found: $1"
        return 1
    fi
    return 0
}

# ==============================================================================
# PREREQUISITES CHECK
# ==============================================================================

check_prerequisites() {
    print_header "Checking Prerequisites"

    local missing=0

    # Check for required commands
    local required_commands=("aws" "jq" "sed" "sha256sum")

    for cmd in "${required_commands[@]}"; do
        if check_command "$cmd"; then
            print_success "$cmd is installed"
        else
            ((missing++))
        fi
    done

    if [ $missing -gt 0 ]; then
        print_error "$missing required command(s) missing"
        echo ""
        print_info "Please install:"
        echo "  - AWS CLI: https://aws.amazon.com/cli/"
        echo "  - jq: sudo apt-get install jq (Ubuntu/Debian) or brew install jq (Mac)"
        return 1
    fi

    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2)
    print_info "AWS CLI version: $aws_version"

    echo ""
    return 0
}

# ==============================================================================
# COLLECT CLIENT INFORMATION
# ==============================================================================

collect_client_info() {
    print_header "Client Information"

    # Client name
    if [ -n "$1" ]; then
        CLIENT_NAME="$1"
        print_info "Using client name from command line: $CLIENT_NAME"
    else
        CLIENT_NAME=$(prompt_input "Client name (lowercase, no spaces)")
    fi

    # Sanitize client name
    CLIENT_NAME=$(echo "$CLIENT_NAME" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | tr -cd '[:alnum:]-')

    print_success "Client name set to: $CLIENT_NAME"

    # Contact information
    CLIENT_CONTACT=$(prompt_input "Primary contact name")
    CLIENT_EMAIL=$(prompt_input "Contact email")

    echo ""
}

# ==============================================================================
# AWS CONFIGURATION
# ==============================================================================

configure_aws() {
    print_header "AWS Configuration"

    # AWS Profile
    print_info "Available AWS profiles:"
    aws configure list-profiles 2>/dev/null || echo "  (none found)"
    echo ""

    AWS_PROFILE=$(prompt_input "AWS profile name" "default")

    # Test AWS credentials
    print_info "Testing AWS credentials..."
    if aws sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null; then
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)
        AWS_USER_ARN=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Arn --output text)
        print_success "AWS credentials valid"
        print_info "Account ID: $AWS_ACCOUNT_ID"
        print_info "User ARN: $AWS_USER_ARN"
    else
        print_error "AWS credentials test failed"
        echo ""
        print_info "Please run: aws configure --profile $AWS_PROFILE"
        return 1
    fi

    echo ""

    # AWS Region
    AWS_REGION=$(prompt_input "AWS region" "us-east-1")

    echo ""
}

# ==============================================================================
# S3 BUCKET CONFIGURATION
# ==============================================================================

configure_s3() {
    print_header "S3 Bucket Configuration"

    # Generate bucket name
    local date_suffix=$(date +%Y%m%d)
    local suggested_bucket="datasync-${CLIENT_NAME}-${date_suffix}"

    BUCKET_NAME=$(prompt_input "S3 bucket name" "$suggested_bucket")

    # Check if bucket exists
    if aws s3 ls "s3://$BUCKET_NAME" --profile "$AWS_PROFILE" 2>/dev/null; then
        print_warning "Bucket already exists: $BUCKET_NAME"
        if ! prompt_yes_no "Use existing bucket?"; then
            BUCKET_NAME=$(prompt_input "Enter different bucket name")
        fi
    fi

    # S3 subdirectory
    S3_SUBDIRECTORY=$(prompt_input "S3 subdirectory (path within bucket)" "datasync")
    S3_SUBDIRECTORY="${S3_SUBDIRECTORY#/}"  # Remove leading slash

    echo ""
}

# ==============================================================================
# LOCAL DIRECTORIES
# ==============================================================================

configure_directories() {
    print_header "Local Directory Configuration"

    # Base directory
    local default_home="$HOME/datasync-${CLIENT_NAME}"
    DATASYNC_HOME=$(prompt_input "DataSync home directory" "$default_home")

    # Subdirectories
    SOURCE_DIR="$DATASYNC_HOME/source"
    LOGS_DIR="$DATASYNC_HOME/logs"
    SCRIPTS_DIR="$DATASYNC_HOME/scripts"

    print_info "Source directory: $SOURCE_DIR"
    print_info "Logs directory: $LOGS_DIR"
    print_info "Scripts directory: $SCRIPTS_DIR"

    echo ""
}

# ==============================================================================
# MONITORING CONFIGURATION
# ==============================================================================

configure_monitoring() {
    print_header "Monitoring Configuration"

    # Log retention
    LOG_RETENTION_DAYS=$(prompt_input "CloudWatch log retention (days)" "30")

    # Monitor interval
    MONITOR_CHECK_INTERVAL=$(prompt_input "Hot folder check interval (seconds)" "30")

    # Email alerts
    if prompt_yes_no "Configure email alerts?" "y"; then
        ALERT_EMAIL=$(prompt_input "Alert email address" "$CLIENT_EMAIL")
        ENABLE_ALERTS="true"
    else
        ALERT_EMAIL=""
        ENABLE_ALERTS="false"
    fi

    # Checksum verification
    if prompt_yes_no "Enable checksum verification?" "y"; then
        ENABLE_CHECKSUM="true"

        print_warning "Post-upload verification downloads all files from S3 (slow/costly)"
        if prompt_yes_no "Enable automatic post-upload verification?" "n"; then
            VERIFY_AFTER_UPLOAD="true"
        else
            VERIFY_AFTER_UPLOAD="false"
        fi
    else
        ENABLE_CHECKSUM="false"
        VERIFY_AFTER_UPLOAD="false"
    fi

    echo ""
}

# ==============================================================================
# GENERATE CONFIGURATION FILE
# ==============================================================================

generate_config() {
    print_header "Generating Configuration"

    local config_file="$DEPLOYMENT_DIR/config/${CLIENT_NAME}-config.env"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # IAM role name
    IAM_ROLE_NAME="DataSyncRole-${CLIENT_NAME}"
    DATASYNC_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}"

    # Log group
    LOG_GROUP="/aws/datasync/${CLIENT_NAME}"
    LOG_GROUP_ARN="arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:${LOG_GROUP}"

    # SNS topic (if alerts enabled)
    if [ "$ENABLE_ALERTS" = "true" ]; then
        SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:datasync-alerts-${CLIENT_NAME}"
    else
        SNS_TOPIC_ARN=""
    fi

    # Copy template
    cp "$DEPLOYMENT_DIR/config/config-template.env" "$config_file"

    # Replace placeholders
    sed -i "s|\[TIMESTAMP\]|$timestamp|g" "$config_file"
    sed -i "s|\[CLIENT_NAME\]|$CLIENT_NAME|g" "$config_file"
    sed -i "s|\[CLIENT_CONTACT\]|$CLIENT_CONTACT|g" "$config_file"
    sed -i "s|\[CLIENT_EMAIL\]|$CLIENT_EMAIL|g" "$config_file"
    sed -i "s|\[DEPLOYMENT_DATE\]|$(date +%Y-%m-%d)|g" "$config_file"
    sed -i "s|\[AWS_PROFILE\]|$AWS_PROFILE|g" "$config_file"
    sed -i "s|\[AWS_REGION\]|$AWS_REGION|g" "$config_file"
    sed -i "s|\[AWS_ACCOUNT_ID\]|$AWS_ACCOUNT_ID|g" "$config_file"
    sed -i "s|\[BUCKET_NAME\]|$BUCKET_NAME|g" "$config_file"
    sed -i "s|\[S3_SUBDIRECTORY\]|$S3_SUBDIRECTORY|g" "$config_file"
    sed -i "s|\[DATASYNC_ROLE_ARN\]|$DATASYNC_ROLE_ARN|g" "$config_file"
    sed -i "s|\[IAM_ROLE_NAME\]|$IAM_ROLE_NAME|g" "$config_file"
    sed -i "s|\[LOG_GROUP\]|$LOG_GROUP|g" "$config_file"
    sed -i "s|\[LOG_GROUP_ARN\]|$LOG_GROUP_ARN|g" "$config_file"
    sed -i "s|\[LOG_RETENTION_DAYS\]|$LOG_RETENTION_DAYS|g" "$config_file"
    sed -i "s|\[PROJECT_TAG\]|datasync-${CLIENT_NAME}|g" "$config_file"
    sed -i "s|\[ENVIRONMENT\]|production|g" "$config_file"
    sed -i "s|\[DATASYNC_HOME\]|$DATASYNC_HOME|g" "$config_file"
    sed -i "s|\[SOURCE_DIR\]|$SOURCE_DIR|g" "$config_file"
    sed -i "s|\[LOGS_DIR\]|$LOGS_DIR|g" "$config_file"
    sed -i "s|\[SCRIPTS_DIR\]|$SCRIPTS_DIR|g" "$config_file"
    sed -i "s|\[MONITOR_CHECK_INTERVAL\]|$MONITOR_CHECK_INTERVAL|g" "$config_file"
    sed -i "s|\[ALERT_EMAIL\]|$ALERT_EMAIL|g" "$config_file"
    sed -i "s|\[SNS_TOPIC_ARN\]|$SNS_TOPIC_ARN|g" "$config_file"
    sed -i "s|ENABLE_CHECKSUM_VERIFICATION=\"true\"|ENABLE_CHECKSUM_VERIFICATION=\"$ENABLE_CHECKSUM\"|g" "$config_file"
    sed -i "s|VERIFY_AFTER_UPLOAD=\"false\"|VERIFY_AFTER_UPLOAD=\"$VERIFY_AFTER_UPLOAD\"|g" "$config_file"

    print_success "Configuration file created: $config_file"

    # Export for use by AWS setup script
    export CONFIG_FILE="$config_file"

    echo ""
}

# ==============================================================================
# CREATE AWS INFRASTRUCTURE
# ==============================================================================

create_aws_infrastructure() {
    print_header "AWS Infrastructure Setup"

    if ! prompt_yes_no "Create AWS infrastructure now?" "y"; then
        print_warning "Skipping AWS infrastructure creation"
        print_info "You can run this later: ./aws-setup/create-infrastructure.sh $CONFIG_FILE"
        return 0
    fi

    # Source the config
    source "$CONFIG_FILE"

    print_info "Creating AWS infrastructure for client: $CLIENT_NAME"
    echo ""

    # Create S3 bucket
    print_info "Creating S3 bucket: $BUCKET_NAME"
    if aws s3 ls "s3://$BUCKET_NAME" --profile "$AWS_PROFILE" 2>/dev/null; then
        print_warning "Bucket already exists, skipping creation"
    else
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3api create-bucket \
                --bucket "$BUCKET_NAME" \
                --region "$AWS_REGION" \
                --profile "$AWS_PROFILE"
        else
            aws s3api create-bucket \
                --bucket "$BUCKET_NAME" \
                --region "$AWS_REGION" \
                --create-bucket-configuration LocationConstraint="$AWS_REGION" \
                --profile "$AWS_PROFILE"
        fi
        print_success "S3 bucket created"
    fi

    # Enable versioning
    print_info "Enabling S3 versioning..."
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled \
        --profile "$AWS_PROFILE"
    print_success "Versioning enabled"

    # Enable encryption
    print_info "Enabling S3 encryption..."
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": true
            }]
        }' \
        --profile "$AWS_PROFILE"
    print_success "Encryption enabled"

    # Block public access
    print_info "Blocking public access..."
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
        --profile "$AWS_PROFILE"
    print_success "Public access blocked"

    # Add tags
    print_info "Adding tags..."
    aws s3api put-bucket-tagging \
        --bucket "$BUCKET_NAME" \
        --tagging "TagSet=[
            {Key=Client,Value=$CLIENT_NAME},
            {Key=Environment,Value=production},
            {Key=ManagedBy,Value=DataSync},
            {Key=DeploymentMode,Value=simulator}
        ]" \
        --profile "$AWS_PROFILE"
    print_success "Tags added"

    echo ""

    # Create IAM role - simplified inline policy
    print_info "Creating IAM role: $IAM_ROLE_NAME"

    # Trust policy
    cat > /tmp/trust-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "datasync.amazonaws.com"},
        "Action": "sts:AssumeRole"
    }]
}
EOF

    # S3 policy
    cat > /tmp/s3-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetBucketLocation",
                "s3:ListBucket",
                "s3:ListBucketMultipartUploads"
            ],
            "Resource": "arn:aws:s3:::$BUCKET_NAME"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:AbortMultipartUpload",
                "s3:DeleteObject",
                "s3:GetObject",
                "s3:GetObjectTagging",
                "s3:GetObjectVersion",
                "s3:ListMultipartUploadParts",
                "s3:PutObject",
                "s3:PutObjectTagging"
            ],
            "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
        }
    ]
}
EOF

    # Create role
    if aws iam get-role --role-name "$IAM_ROLE_NAME" --profile "$AWS_PROFILE" 2>/dev/null; then
        print_warning "IAM role already exists"
    else
        aws iam create-role \
            --role-name "$IAM_ROLE_NAME" \
            --assume-role-policy-document file:///tmp/trust-policy.json \
            --tags "Key=Client,Value=$CLIENT_NAME" "Key=Environment,Value=production" \
            --profile "$AWS_PROFILE"
        print_success "IAM role created"
    fi

    # Attach S3 policy
    print_info "Attaching S3 policy..."
    aws iam put-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-name "S3Access" \
        --policy-document file:///tmp/s3-policy.json \
        --profile "$AWS_PROFILE"
    print_success "S3 policy attached"

    # Clean up temp files
    rm -f /tmp/trust-policy.json /tmp/s3-policy.json

    echo ""

    # Create CloudWatch log group
    print_info "Creating CloudWatch log group: $LOG_GROUP"
    if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --profile "$AWS_PROFILE" --region "$AWS_REGION" 2>/dev/null | grep -q "$LOG_GROUP"; then
        print_warning "Log group already exists"
    else
        aws logs create-log-group \
            --log-group-name "$LOG_GROUP" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION"
        print_success "Log group created"
    fi

    # Set retention policy
    print_info "Setting log retention to $LOG_RETENTION_DAYS days..."
    aws logs put-retention-policy \
        --log-group-name "$LOG_GROUP" \
        --retention-in-days "$LOG_RETENTION_DAYS" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION"
    print_success "Retention policy set"

    echo ""

    # Create SNS topic if alerts enabled
    if [ "$ENABLE_ALERTS" = "true" ]; then
        print_info "Creating SNS topic for alerts..."

        local topic_name="datasync-alerts-${CLIENT_NAME}"
        local created_topic_arn=$(aws sns create-topic \
            --name "$topic_name" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --query 'TopicArn' \
            --output text)

        print_success "SNS topic created: $created_topic_arn"

        # Subscribe email
        print_info "Subscribing email: $ALERT_EMAIL"
        aws sns subscribe \
            --topic-arn "$created_topic_arn" \
            --protocol email \
            --notification-endpoint "$ALERT_EMAIL" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION"

        print_success "Email subscription created"
        print_warning "Check $ALERT_EMAIL and confirm the SNS subscription"

        echo ""
    fi

    print_success "AWS infrastructure created successfully!"
    echo ""
}

# ==============================================================================
# GENERATE DEPLOYMENT PACKAGE
# ==============================================================================

generate_deployment_package() {
    print_header "Generating Deployment Package"

    local package_dir="$DEPLOYMENT_DIR/packages/${CLIENT_NAME}-deployment"

    # Create package directory
    mkdir -p "$package_dir"/{scripts,config,docs}

    # Copy scripts
    print_info "Copying scripts..."
    cp "$DEPLOYMENT_DIR"/scripts/*.sh "$package_dir/scripts/"
    print_success "Scripts copied"

    # Copy config
    print_info "Copying configuration..."
    cp "$CONFIG_FILE" "$package_dir/config/datasync-config.env"
    print_success "Configuration copied"

    # Copy documentation
    print_info "Copying documentation..."
    if [ -d "$DEPLOYMENT_DIR/docs" ]; then
        cp "$DEPLOYMENT_DIR"/docs/*.md "$package_dir/docs/" 2>/dev/null || true
    fi
    print_success "Documentation copied"

    # Create install script
    print_info "Creating installation script..."
    cat > "$package_dir/install.sh" <<'INSTALL_EOF'
#!/bin/bash
# DataSync Simulator Installation Script
# This script installs the DataSync simulator on the client system

set -e

echo "==============================================="
echo "DataSync Simulator Installation"
echo "==============================================="
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration
if [ ! -f "$SCRIPT_DIR/config/datasync-config.env" ]; then
    echo "ERROR: Configuration file not found!"
    exit 1
fi

source "$SCRIPT_DIR/config/datasync-config.env"

echo "Client: $CLIENT_NAME"
echo "Home directory: $DATASYNC_HOME"
echo ""

# Create directories
echo "Creating directories..."
mkdir -p "$SOURCE_DIR"
mkdir -p "$LOGS_DIR"
mkdir -p "$SCRIPTS_DIR"
mkdir -p "$LOGS_DIR/checksums"

echo "✓ Directories created"
echo ""

# Copy scripts
echo "Installing scripts..."
cp "$SCRIPT_DIR"/scripts/*.sh "$SCRIPTS_DIR/"
chmod +x "$SCRIPTS_DIR"/*.sh

echo "✓ Scripts installed"
echo ""

# Copy configuration
echo "Installing configuration..."
cp "$SCRIPT_DIR/config/datasync-config.env" "$HOME/datasync-config.env"

echo "✓ Configuration installed to: $HOME/datasync-config.env"
echo ""

# Test AWS connectivity
echo "Testing AWS connectivity..."
if aws sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null; then
    echo "✓ AWS credentials valid"
else
    echo "⚠ WARNING: AWS credentials test failed"
    echo "  Please run: aws configure --profile $AWS_PROFILE"
fi
echo ""

# Create test file
echo "Creating test file..."
echo "Test installation - $(date)" > "$SOURCE_DIR/test-installation.txt"
echo "✓ Test file created: $SOURCE_DIR/test-installation.txt"
echo ""

echo "==============================================="
echo "Installation Complete!"
echo "==============================================="
echo ""
echo "Next steps:"
echo "1. Source configuration: source ~/datasync-config.env"
echo "2. Start monitor: cd $SCRIPTS_DIR && ./start-monitor.sh"
echo "3. Or manual sync: cd $SCRIPTS_DIR && ./sync-now.sh"
echo ""
echo "Hot folder: $SOURCE_DIR"
echo "Logs: $LOGS_DIR"
echo ""
INSTALL_EOF

    chmod +x "$package_dir/install.sh"
    print_success "Installation script created"

    # Create README
    cat > "$package_dir/README.md" <<README_EOF
# DataSync Simulator - Client Deployment Package

**Client**: $CLIENT_NAME
**Generated**: $(date)
**Mode**: Simulator (AWS CLI-based)

## Quick Start

### 1. Installation

\`\`\`bash
cd $(basename $package_dir)
./install.sh
\`\`\`

### 2. Start Monitoring

\`\`\`bash
source ~/datasync-config.env
cd \$SCRIPTS_DIR
./start-monitor.sh
\`\`\`

### 3. Add Files

Copy files to the hot folder:
\`\`\`bash
cp your-files/* \$SOURCE_DIR/
\`\`\`

Files will automatically sync to S3 within 30 seconds.

## Configuration

- **Configuration file**: \`~/datasync-config.env\`
- **Hot folder**: \`$SOURCE_DIR\`
- **S3 bucket**: \`$BUCKET_NAME\`
- **S3 path**: \`$BUCKET_NAME/$S3_SUBDIRECTORY/\`

## Commands

| Command | Purpose |
|---------|---------|
| \`./start-monitor.sh\` | Start hot folder monitoring |
| \`./stop-monitor.sh\` | Stop monitoring |
| \`./sync-now.sh\` | Manual sync trigger |
| \`./check-status.sh\` | Check sync status |
| \`./verify-checksums.sh\` | Verify file integrity |

## Documentation

See \`docs/\` directory for:
- Operations manual
- Troubleshooting guide
- Migration to DataSync agent

## Support

Contact: $CLIENT_CONTACT ($CLIENT_EMAIL)

---

Generated with DataSync Client Setup Tool
README_EOF

    print_success "README created"
    echo ""

    # Create tarball
    print_info "Creating deployment package archive..."
    cd "$DEPLOYMENT_DIR/packages"
    tar -czf "${CLIENT_NAME}-deployment.tar.gz" "$(basename $package_dir)"
    cd - > /dev/null

    local package_path="$DEPLOYMENT_DIR/packages/${CLIENT_NAME}-deployment.tar.gz"
    local package_size=$(du -h "$package_path" | cut -f1)

    print_success "Deployment package created: $package_path"
    print_info "Package size: $package_size"

    echo ""
}

# ==============================================================================
# SUMMARY
# ==============================================================================

print_summary() {
    print_header "Setup Summary"

    cat <<SUMMARY

Client Information:
  Name: $CLIENT_NAME
  Contact: $CLIENT_CONTACT
  Email: $CLIENT_EMAIL

AWS Configuration:
  Profile: $AWS_PROFILE
  Account: $AWS_ACCOUNT_ID
  Region: $AWS_REGION

S3 Configuration:
  Bucket: $BUCKET_NAME
  Path: $S3_SUBDIRECTORY
  Storage Class: INTELLIGENT_TIERING

Local Directories:
  Home: $DATASYNC_HOME
  Source: $SOURCE_DIR
  Logs: $LOGS_DIR
  Scripts: $SCRIPTS_DIR

Features:
  Checksum Verification: $ENABLE_CHECKSUM
  Post-Upload Verification: $VERIFY_AFTER_UPLOAD
  Email Alerts: $ENABLE_ALERTS
  Monitor Interval: ${MONITOR_CHECK_INTERVAL}s

Files Created:
  Configuration: $CONFIG_FILE
  Package: $DEPLOYMENT_DIR/packages/${CLIENT_NAME}-deployment.tar.gz

SUMMARY

    if [ "$ENABLE_ALERTS" = "true" ]; then
        echo "⚠ IMPORTANT: Check email ($ALERT_EMAIL) to confirm SNS subscription"
        echo ""
    fi

    print_success "Client setup complete!"
    echo ""

    print_info "Next steps:"
    echo "  1. Review configuration: cat $CONFIG_FILE"
    echo "  2. Transfer package to client: scp packages/${CLIENT_NAME}-deployment.tar.gz client:"
    echo "  3. On client machine: tar -xzf ${CLIENT_NAME}-deployment.tar.gz && cd ${CLIENT_NAME}-deployment && ./install.sh"
    echo ""
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    clear

    print_header "DataSync Client Setup Wizard"

    echo "This wizard will help you set up a DataSync simulator deployment for a new client."
    echo ""

    # Check prerequisites
    check_prerequisites || exit 1

    # Collect information
    collect_client_info "$1"
    configure_aws || exit 1
    configure_s3
    configure_directories
    configure_monitoring

    # Generate configuration
    generate_config

    # Create AWS infrastructure
    create_aws_infrastructure

    # Generate deployment package
    generate_deployment_package

    # Summary
    print_summary
}

# Run main function
main "$@"
