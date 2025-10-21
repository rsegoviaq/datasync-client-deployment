#!/bin/bash
# ==============================================================================
# DataSync Migration Cutover Script
# ==============================================================================
# Purpose: Switch from simulator to full DataSync agent
# Usage: ./cutover-to-datasync.sh [--force]
# ==============================================================================

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load configuration
if [ -f ~/datasync-config.env ]; then
    source ~/datasync-config.env
else
    echo -e "${RED}✗ Configuration file not found: ~/datasync-config.env${NC}"
    exit 1
fi

FORCE_MODE=false
if [ "$1" = "--force" ]; then
    FORCE_MODE=true
fi

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}DataSync Migration Cutover${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

echo "Client: $CLIENT_NAME"
echo "Current mode: $DEPLOYMENT_MODE"
echo ""

# ==============================================================================
# PRE-FLIGHT CHECKS
# ==============================================================================

echo -e "${BLUE}Running pre-flight checks...${NC}"
echo ""

# Check if agent is configured
if [ -z "$AGENT_ARN" ]; then
    echo -e "${RED}✗ DataSync agent not configured${NC}"
    echo "  Please run the agent deployment first"
    exit 1
fi

# Check if task is configured
if [ -z "$TASK_ARN" ]; then
    echo -e "${RED}✗ DataSync task not configured${NC}"
    echo "  Please complete agent setup first"
    exit 1
fi

# Verify agent status
echo "Checking agent status..."
AGENT_STATUS=$(aws datasync describe-agent \
    --agent-arn "$AGENT_ARN" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'Status' \
    --output text 2>/dev/null || echo "ERROR")

if [ "$AGENT_STATUS" = "ONLINE" ]; then
    echo -e "${GREEN}✓${NC} DataSync agent online"
elif [ "$FORCE_MODE" = false ]; then
    echo -e "${RED}✗${NC} DataSync agent status: $AGENT_STATUS"
    echo "  Agent must be ONLINE before cutover"
    echo "  Use --force to override"
    exit 1
else
    echo -e "${YELLOW}⚠${NC} DataSync agent status: $AGENT_STATUS (forcing anyway)"
fi

echo ""

# ==============================================================================
# FINAL SIMULATOR SYNC
# ==============================================================================

echo -e "${BLUE}Performing final simulator sync...${NC}"
echo ""

if [ -f "$SCRIPTS_DIR/sync-now.sh" ]; then
    echo "Running one last sync with simulator..."
    cd "$SCRIPTS_DIR"
    ./sync-now.sh || true
    echo ""
    echo -e "${GREEN}✓${NC} Final simulator sync complete"
else
    echo -e "${YELLOW}⚠${NC} Simulator script not found, skipping final sync"
fi

echo ""

# ==============================================================================
# STOP SIMULATOR
# ==============================================================================

echo -e "${BLUE}Stopping simulator...${NC}"
echo ""

# Stop hot folder monitor
if pgrep -f "hotfolder-monitor.sh" > /dev/null; then
    echo "Stopping hot folder monitor..."
    pkill -f "hotfolder-monitor.sh" || true
    sleep 2
    echo -e "${GREEN}✓${NC} Hot folder monitor stopped"
else
    echo "Hot folder monitor not running"
fi

# Disable simulator scripts (rename them)
if [ -f "$SCRIPTS_DIR/start-monitor.sh" ]; then
    mv "$SCRIPTS_DIR/start-monitor.sh" "$SCRIPTS_DIR/start-monitor.sh.disabled" || true
    echo -e "${GREEN}✓${NC} Simulator scripts disabled"
fi

echo ""

# ==============================================================================
# VERIFY DATASYNC TASK
# ==============================================================================

echo -e "${BLUE}Verifying DataSync task configuration...${NC}"
echo ""

TASK_STATUS=$(aws datasync describe-task \
    --task-arn "$TASK_ARN" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'Status' \
    --output text 2>/dev/null || echo "ERROR")

if [ "$TASK_STATUS" = "AVAILABLE" ]; then
    echo -e "${GREEN}✓${NC} DataSync task status: $TASK_STATUS"
else
    echo -e "${YELLOW}⚠${NC} DataSync task status: $TASK_STATUS"
fi

echo ""

# ==============================================================================
# INITIAL DATASYNC EXECUTION
# ==============================================================================

echo -e "${BLUE}Starting initial DataSync execution...${NC}"
echo ""

echo "This will sync all files from source to S3 using DataSync agent..."
if [ "$FORCE_MODE" = false ]; then
    read -p "Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Cutover cancelled"
        exit 0
    fi
fi

echo ""
echo "Starting DataSync task execution..."

EXECUTION_ARN=$(aws datasync start-task-execution \
    --task-arn "$TASK_ARN" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query "TaskExecutionArn" \
    --output text)

echo -e "${GREEN}✓${NC} DataSync execution started"
echo "Execution ARN: $EXECUTION_ARN"
echo ""

# Monitor execution
echo "Monitoring execution (this may take several minutes)..."
echo ""

LAST_STATUS=""
while true; do
    STATUS=$(aws datasync describe-task-execution \
        --task-execution-arn "$EXECUTION_ARN" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query 'Status' \
        --output text 2>/dev/null || echo "UNKNOWN")

    BYTES=$(aws datasync describe-task-execution \
        --task-execution-arn "$EXECUTION_ARN" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query 'BytesTransferred' \
        --output text 2>/dev/null || echo "0")

    FILES=$(aws datasync describe-task-execution \
        --task-execution-arn "$EXECUTION_ARN" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --query 'FilesTransferred' \
        --output text 2>/dev/null || echo "0")

    if [ "$STATUS" != "$LAST_STATUS" ]; then
        echo "[$(date '+%H:%M:%S')] Status: $STATUS | Files: $FILES | Bytes: $BYTES"
        LAST_STATUS="$STATUS"
    fi

    if [ "$STATUS" = "SUCCESS" ] || [ "$STATUS" = "ERROR" ]; then
        break
    fi

    sleep 10
done

echo ""

if [ "$STATUS" = "SUCCESS" ]; then
    echo -e "${GREEN}✓ Initial DataSync execution completed successfully!${NC}"
    echo "  Files transferred: $FILES"
    echo "  Bytes transferred: $BYTES"
else
    echo -e "${RED}✗ DataSync execution failed: $STATUS${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check CloudWatch logs: aws logs tail $LOG_GROUP --follow"
    echo "  2. Verify agent connectivity"
    echo "  3. Check source location accessibility"
    exit 1
fi

echo ""

# ==============================================================================
# UPDATE CONFIGURATION
# ==============================================================================

echo -e "${BLUE}Updating configuration...${NC}"
echo ""

# Update deployment mode
if grep -q "DEPLOYMENT_MODE=" ~/datasync-config.env; then
    sed -i 's/DEPLOYMENT_MODE="simulator"/DEPLOYMENT_MODE="agent"/' ~/datasync-config.env
    echo -e "${GREEN}✓${NC} Deployment mode updated to: agent"
else
    echo 'export DEPLOYMENT_MODE="agent"' >> ~/datasync-config.env
    echo -e "${GREEN}✓${NC} Deployment mode set to: agent"
fi

# Reload configuration
source ~/datasync-config.env

echo ""

# ==============================================================================
# SETUP DATASYNC SCHEDULE
# ==============================================================================

echo -e "${BLUE}Setting up DataSync schedule...${NC}"
echo ""

echo "DataSync task can run on a schedule or manually"
echo "Current task schedule: Check AWS Console"
echo ""

echo -e "${GREEN}✓${NC} DataSync agent is now active"
echo ""

# ==============================================================================
# BACKUP SIMULATOR
# ==============================================================================

echo -e "${BLUE}Backing up simulator configuration...${NC}"
echo ""

BACKUP_DIR="$DATASYNC_HOME/simulator-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup scripts
if [ -d "$SCRIPTS_DIR" ]; then
    cp -r "$SCRIPTS_DIR" "$BACKUP_DIR/" || true
fi

# Backup logs
if [ -d "$LOGS_DIR" ]; then
    cp -r "$LOGS_DIR" "$BACKUP_DIR/" || true
fi

echo -e "${GREEN}✓${NC} Simulator backup saved to: $BACKUP_DIR"
echo ""

# ==============================================================================
# SUMMARY
# ==============================================================================

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Migration Cutover Complete!${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

echo "Status:"
echo "  Previous mode: simulator"
echo "  Current mode: agent"
echo "  Agent status: $AGENT_STATUS"
echo "  Task status: $TASK_STATUS"
echo ""

echo "DataSync Configuration:"
echo "  Agent ARN: $AGENT_ARN"
echo "  Task ARN: $TASK_ARN"
echo "  Source: $SOURCE_LOCATION_ARN"
echo "  Destination: $DEST_LOCATION_ARN"
echo ""

echo "Next Steps:"
echo "  1. Monitor DataSync executions in AWS Console"
echo "  2. Set up automated schedule (if not already configured)"
echo "  3. Configure CloudWatch alarms"
echo "  4. Test manual execution: aws datasync start-task-execution --task-arn $TASK_ARN"
echo ""

echo "Simulator backup:"
echo "  Location: $BACKUP_DIR"
echo "  Keep for 30 days as rollback option"
echo ""

echo "Rollback procedure (if needed):"
echo "  1. Stop DataSync task"
echo "  2. Re-enable simulator scripts:"
echo "     mv $SCRIPTS_DIR/start-monitor.sh.disabled $SCRIPTS_DIR/start-monitor.sh"
echo "  3. Update DEPLOYMENT_MODE back to 'simulator'"
echo "  4. Start monitor: $SCRIPTS_DIR/start-monitor.sh"
echo ""

echo -e "${GREEN}✓ Migration to DataSync agent complete!${NC}"
echo ""
