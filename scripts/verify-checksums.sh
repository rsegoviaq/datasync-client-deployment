#!/bin/bash
# Verify S3 files against stored checksums
# Can verify against a specific checksum file or the most recent one

# Load configuration (look in deployment folder, relative to script location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../datasync-config.env"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "❌ Configuration file not found: $CONFIG_FILE"
    echo "Expected location: deployment_folder/datasync-config.env"
    exit 1
fi

# Script configuration
LOG_DIR="$LOGS_DIR"
CHECKSUM_DIR="$LOG_DIR/checksums"
S3_DEST="s3://$BUCKET_NAME/$S3_SUBDIRECTORY/"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Usage
show_usage() {
    echo "Usage: $0 [CHECKSUM_FILE]"
    echo ""
    echo "Verify files in S3 against stored checksums."
    echo ""
    echo "Arguments:"
    echo "  CHECKSUM_FILE  Path to checksum file (optional)"
    echo "                 If not provided, uses the most recent checksum file"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 ~/datasync-test/logs/checksums/checksums-20251016-143022.txt"
}

# Check arguments
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_usage
    exit 0
fi

# Determine checksum file to use
if [ -n "$1" ]; then
    CHECKSUM_FILE="$1"
    if [ ! -f "$CHECKSUM_FILE" ]; then
        echo -e "${RED}❌ Checksum file not found: $CHECKSUM_FILE${NC}"
        exit 1
    fi
else
    # Find most recent checksum file
    CHECKSUM_FILE=$(ls -t "$CHECKSUM_DIR"/checksums-*.txt 2>/dev/null | head -1)
    if [ -z "$CHECKSUM_FILE" ]; then
        echo -e "${RED}❌ No checksum files found in $CHECKSUM_DIR${NC}"
        echo "Run a sync first to generate checksums."
        exit 1
    fi
    echo -e "${BLUE}Using most recent checksum file: $CHECKSUM_FILE${NC}"
fi

echo ""
echo -e "${GREEN}======================================"
echo "Checksum Verification"
echo "======================================${NC}"
echo "Checksum file: $CHECKSUM_FILE"
echo "S3 destination: $S3_DEST"
echo ""

# Counters
TOTAL=0
VERIFIED=0
ERRORS=0
TEMP_DIR=$(mktemp -d)

echo -e "${BLUE}Verifying files...${NC}"
echo ""

# Read and verify each file
while IFS= read -r line; do
    EXPECTED_CHECKSUM=$(echo "$line" | awk '{print $1}')
    FILE_PATH=$(echo "$line" | cut -d' ' -f3-)
    S3_PATH="${S3_DEST}${FILE_PATH}"
    TEMP_FILE="$TEMP_DIR/$(basename "$FILE_PATH")"

    ((TOTAL++))

    # Download file from S3
    printf "  Verifying: %-50s " "$FILE_PATH"

    if aws s3 cp "$S3_PATH" "$TEMP_FILE" --profile "$AWS_PROFILE" --region "$AWS_REGION" --quiet 2>/dev/null; then
        # Calculate checksum of downloaded file
        ACTUAL_CHECKSUM=$(sha256sum "$TEMP_FILE" | awk '{print $1}')

        if [ "$EXPECTED_CHECKSUM" = "$ACTUAL_CHECKSUM" ]; then
            echo -e "${GREEN}✓${NC}"
            ((VERIFIED++))
        else
            echo -e "${RED}✗ MISMATCH${NC}"
            echo -e "${RED}    Expected: $EXPECTED_CHECKSUM${NC}"
            echo -e "${RED}    Actual:   $ACTUAL_CHECKSUM${NC}"
            ((ERRORS++))
        fi

        rm -f "$TEMP_FILE"
    else
        echo -e "${YELLOW}✗ NOT FOUND IN S3${NC}"
        ((ERRORS++))
    fi
done < "$CHECKSUM_FILE"

# Cleanup
rm -rf "$TEMP_DIR"

# Summary
echo ""
echo -e "${GREEN}======================================"
echo "Verification Summary"
echo "======================================${NC}"
echo "Total files:     $TOTAL"
echo -e "Verified:        ${GREEN}$VERIFIED${NC}"
echo -e "Errors:          ${RED}$ERRORS${NC}"
echo ""

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✅ All checksums verified successfully!${NC}"
    exit 0
else
    echo -e "${RED}❌ Verification failed with $ERRORS errors${NC}"
    exit 1
fi
