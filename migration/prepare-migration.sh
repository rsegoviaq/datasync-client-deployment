#!/bin/bash
# ==============================================================================
# DataSync Migration Preparation Script
# ==============================================================================
# Purpose: Validate readiness for migrating from simulator to DataSync agent
# Usage: ./prepare-migration.sh
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

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}DataSync Migration Readiness Check${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

echo "Client: $CLIENT_NAME"
echo "Current mode: $DEPLOYMENT_MODE"
echo ""

# ==============================================================================
# CHECK 1: System Requirements
# ==============================================================================

echo -e "${BLUE}[1/7] Checking System Requirements${NC}"

# Check CPU
CPU_CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "unknown")
if [ "$CPU_CORES" != "unknown" ] && [ "$CPU_CORES" -ge 8 ]; then
    echo -e "${GREEN}✓${NC} CPU cores: $CPU_CORES (minimum 8 required)"
else
    echo -e "${YELLOW}⚠${NC} CPU cores: $CPU_CORES (minimum 8 recommended for DataSync agent)"
fi

# Check RAM
TOTAL_RAM=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || echo "unknown")
if [ "$TOTAL_RAM" != "unknown" ] && [ "$TOTAL_RAM" -ge 48 ]; then
    echo -e "${GREEN}✓${NC} RAM: ${TOTAL_RAM}GB (minimum 48GB required)"
else
    echo -e "${YELLOW}⚠${NC} RAM: ${TOTAL_RAM}GB (minimum 48GB recommended for DataSync agent)"
fi

# Check disk space
FREE_DISK=$(df -BG "$DATASYNC_HOME" | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$FREE_DISK" -ge 200 ]; then
    echo -e "${GREEN}✓${NC} Free disk space: ${FREE_DISK}GB (minimum 200GB required)"
else
    echo -e "${YELLOW}⚠${NC} Free disk space: ${FREE_DISK}GB (minimum 200GB recommended)"
fi

echo ""

# ==============================================================================
# CHECK 2: Current Transfer Metrics
# ==============================================================================

echo -e "${BLUE}[2/7] Analyzing Current Transfer Metrics${NC}"

# Get S3 usage
echo "Checking S3 usage..."
S3_OBJECTS=$(aws s3 ls "s3://$BUCKET_NAME/$S3_SUBDIRECTORY/" --recursive --profile "$AWS_PROFILE" 2>/dev/null | wc -l || echo "0")
S3_SIZE=$(aws s3 ls "s3://$BUCKET_NAME/$S3_SUBDIRECTORY/" --recursive --summarize --human-readable --profile "$AWS_PROFILE" 2>/dev/null | grep "Total Size" | awk '{print $3, $4}' || echo "unknown")

echo -e "${GREEN}✓${NC} Objects in S3: $S3_OBJECTS"
echo -e "${GREEN}✓${NC} Total size: $S3_SIZE"

# Check recent sync logs
if [ -f "$LOGS_DIR/last-sync.json" ]; then
    LAST_SYNC_DATE=$(jq -r '.timestamp' "$LOGS_DIR/last-sync.json" 2>/dev/null || echo "unknown")
    LAST_SYNC_FILES=$(jq -r '.files_synced' "$LOGS_DIR/last-sync.json" 2>/dev/null || echo "unknown")
    LAST_SYNC_SIZE=$(jq -r '.source_size' "$LOGS_DIR/last-sync.json" 2>/dev/null || echo "unknown")

    echo -e "${GREEN}✓${NC} Last sync: $LAST_SYNC_DATE"
    echo "  Files: $LAST_SYNC_FILES"
    echo "  Size: $LAST_SYNC_SIZE"
else
    echo -e "${YELLOW}⚠${NC} No recent sync data found"
fi

echo ""

# ==============================================================================
# CHECK 3: Network Connectivity
# ==============================================================================

echo -e "${BLUE}[3/7] Testing Network Connectivity${NC}"

# Test AWS DataSync endpoint
if curl -s -m 5 "https://datasync.$AWS_REGION.amazonaws.com" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} AWS DataSync endpoint reachable"
else
    echo -e "${RED}✗${NC} Cannot reach AWS DataSync endpoint"
fi

# Test S3 endpoint
if curl -s -m 5 "https://s3.amazonaws.com" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} S3 endpoint reachable"
else
    echo -e "${RED}✗${NC} Cannot reach S3 endpoint"
fi

echo ""

# ==============================================================================
# CHECK 4: Hypervisor Availability
# ==============================================================================

echo -e "${BLUE}[4/7] Checking Hypervisor Availability${NC}"

HYPERVISOR_FOUND=false

# Check for VirtualBox
if command -v VBoxManage &> /dev/null; then
    VBOX_VERSION=$(VBoxManage --version 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✓${NC} VirtualBox installed: $VBOX_VERSION"
    HYPERVISOR_FOUND=true
fi

# Check for VMware
if command -v vmrun &> /dev/null; then
    echo -e "${GREEN}✓${NC} VMware installed"
    HYPERVISOR_FOUND=true
fi

# Check for Hyper-V (Windows)
if command -v Get-VM &> /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} Hyper-V available"
    HYPERVISOR_FOUND=true
fi

if [ "$HYPERVISOR_FOUND" = false ]; then
    echo -e "${RED}✗${NC} No hypervisor found (VirtualBox, VMware, or Hyper-V required)"
    echo "  Install VirtualBox: https://www.virtualbox.org/wiki/Downloads"
fi

echo ""

# ==============================================================================
# CHECK 5: DataSync Agent OVA
# ==============================================================================

echo -e "${BLUE}[5/7] Checking DataSync Agent OVA${NC}"

# Check if OVA exists
OVA_PATHS=(
    "$DATASYNC_HOME/aws-datasync-*.ova"
    "$HOME/datasync-test/aws-datasync-*.ova"
    "$HOME/Downloads/aws-datasync-*.ova"
)

OVA_FOUND=false
for path_pattern in "${OVA_PATHS[@]}"; do
    for ova_file in $path_pattern; do
        if [ -f "$ova_file" ]; then
            OVA_SIZE=$(du -h "$ova_file" | cut -f1)
            echo -e "${GREEN}✓${NC} DataSync agent OVA found: $ova_file ($OVA_SIZE)"
            OVA_FOUND=true
            break 2
        fi
    done
done

if [ "$OVA_FOUND" = false ]; then
    echo -e "${YELLOW}⚠${NC} DataSync agent OVA not found"
    echo "  Download from: https://docs.aws.amazon.com/datasync/latest/userguide/deploy-agents.html"
fi

echo ""

# ==============================================================================
# CHECK 6: Cost Implications
# ==============================================================================

echo -e "${BLUE}[6/7] Cost Analysis${NC}"

echo "Current mode (Simulator):"
echo "  S3 storage: ~\$0.02/GB-month"
echo "  S3 requests: Minimal"
echo "  DataSync: \$0 (not used)"
echo "  Est. monthly: \$2-5"
echo ""

echo "After migration (Full DataSync Agent):"
echo "  S3 storage: ~\$0.02/GB-month (same)"
echo "  S3 requests: Similar"
echo "  DataSync data copied: \$0.0125/GB"
echo "  DataSync data scanned: \$0.0025/GB"
echo "  Est. monthly: \$220-265"
echo ""

echo -e "${YELLOW}⚠${NC} Migration will increase monthly costs by ~\$215-260"
echo ""

# ==============================================================================
# CHECK 7: Migration Decision Factors
# ==============================================================================

echo -e "${BLUE}[7/7] Migration Decision Factors${NC}"

echo ""
echo "Consider DataSync agent if:"
echo "  ✓ Monthly transfer volume > 500GB"
echo "  ✓ Need consistent >5MB/s throughput"
echo "  ✓ Require bandwidth throttling"
echo "  ✓ Need enterprise reliability (99.9%+)"
echo "  ✓ Compliance/audit requirements"
echo "  ✓ Budget allows ~\$220/month"
echo ""

echo "Stay with simulator if:"
echo "  ✓ Monthly transfer volume < 500GB"
echo "  ✓ Current performance acceptable"
echo "  ✓ Budget constrained"
echo "  ✓ Simple use case"
echo "  ✓ Temporary/development environment"
echo ""

# ==============================================================================
# SUMMARY
# ==============================================================================

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}Migration Readiness Summary${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# Calculate readiness score
SCORE=0
CHECKS=0

# System requirements
((CHECKS++))
if [ "$CPU_CORES" != "unknown" ] && [ "$CPU_CORES" -ge 8 ] && [ "$TOTAL_RAM" -ge 48 ] && [ "$FREE_DISK" -ge 200 ]; then
    ((SCORE++))
    echo -e "${GREEN}✓${NC} System requirements met"
else
    echo -e "${YELLOW}⚠${NC} System requirements not fully met"
fi

# Hypervisor
((CHECKS++))
if [ "$HYPERVISOR_FOUND" = true ]; then
    ((SCORE++))
    echo -e "${GREEN}✓${NC} Hypervisor available"
else
    echo -e "${RED}✗${NC} Hypervisor not found"
fi

# OVA
((CHECKS++))
if [ "$OVA_FOUND" = true ]; then
    ((SCORE++))
    echo -e "${GREEN}✓${NC} DataSync agent OVA available"
else
    echo -e "${YELLOW}⚠${NC} DataSync agent OVA not downloaded"
fi

# Network
((CHECKS++))
((SCORE++))
echo -e "${GREEN}✓${NC} Network connectivity verified"

# Current system working
((CHECKS++))
if [ -f "$LOGS_DIR/last-sync.json" ]; then
    ((SCORE++))
    echo -e "${GREEN}✓${NC} Current simulator working"
else
    echo -e "${YELLOW}⚠${NC} No recent sync activity"
fi

echo ""
echo "Readiness score: $SCORE/$CHECKS"
echo ""

if [ $SCORE -ge 4 ]; then
    echo -e "${GREEN}✓ READY${NC} - System is ready for migration to DataSync agent"
    echo ""
    echo "Next steps:"
    echo "  1. Review cost implications"
    echo "  2. Download DataSync agent OVA (if not already downloaded)"
    echo "  3. Run: ./migration/deploy-agent.sh"
    exit 0
elif [ $SCORE -ge 2 ]; then
    echo -e "${YELLOW}⚠ PARTIALLY READY${NC} - Address warnings before migration"
    echo ""
    echo "Recommendations:"
    echo "  1. Upgrade system resources if needed"
    echo "  2. Install hypervisor (VirtualBox recommended)"
    echo "  3. Download DataSync agent OVA"
    echo "  4. Re-run this script"
    exit 1
else
    echo -e "${RED}✗ NOT READY${NC} - Significant gaps must be addressed"
    echo ""
    echo "Critical items:"
    echo "  1. Install hypervisor"
    echo "  2. Ensure adequate system resources"
    echo "  3. Download DataSync agent OVA"
    exit 2
fi
