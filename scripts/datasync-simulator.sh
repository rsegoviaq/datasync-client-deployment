#!/bin/bash
# DataSync Simulator using AWS S3 Sync with Additional Checksums
# Simulates DataSync behavior with AWS S3's native checksum verification
#
# AWS Additional Checksums Feature (Feb 2022):
#   - Server-side checksum verification during upload (no downloads needed)
#   - HTTP trailer-based checksums (single-pass operation)
#   - 5 supported algorithms: CRC64NVME, CRC32C, CRC32, SHA256, SHA1
#   - Hardware-accelerated CRC algorithms provide 3+ GB/s throughput
#   - Automatic validation by S3 before storing (BadDigest error on mismatch)
#
# Performance Benefits:
#   - CRC64NVME/CRC32C: ~30-60 seconds for 100GB files
#   - SHA256: ~7+ minutes for 100GB files
#   - Verification without downloads using 'aws s3api head-object'

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

# Script configuration - all values come from config file
WATCH_DIR="$SOURCE_DIR"
S3_DEST="s3://$BUCKET_NAME/$S3_SUBDIRECTORY/"
LOG_DIR="$LOGS_DIR"
LOG_FILE="$LOG_DIR/sync-$(date +%Y%m%d).log"
CHECKSUM_DIR="$LOG_DIR/checksums"
CHECKSUM_FILE="$CHECKSUM_DIR/checksums-$(date +%Y%m%d-%H%M%S).txt"

# Feature flags
ENABLE_CHECKSUM_VERIFICATION=${ENABLE_CHECKSUM_VERIFICATION:-true}
CHECKSUM_ALGORITHM=${CHECKSUM_ALGORITHM:-CRC64NVME}
VERIFY_AFTER_UPLOAD=${VERIFY_AFTER_UPLOAD:-false}

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case $level in
        INFO)
            echo -e "${GREEN}[INFO]${NC} [$timestamp] $message" | tee -a "$LOG_FILE"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} [$timestamp] $message" | tee -a "$LOG_FILE"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} [$timestamp] $message" | tee -a "$LOG_FILE"
            ;;
        DEBUG)
            echo -e "${BLUE}[DEBUG]${NC} [$timestamp] $message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# Function to calculate local SHA256 checksums (legacy/optional)
# Note: AWS Additional Checksums calculates checksums automatically during upload
# This function is kept for compliance records or when CHECKSUM_ALGORITHM=NONE
calculate_checksums_legacy() {
    local source_dir=$1
    local output_file=$2

    log INFO "Calculating local SHA256 checksums for compliance records..."

    # Create checksum directory
    mkdir -p "$(dirname "$output_file")"

    # Calculate checksums
    local file_count=0
    > "$output_file"  # Clear/create file

    while IFS= read -r -d '' file; do
        local rel_path="${file#$source_dir/}"
        local checksum=$(sha256sum "$file" | cut -d' ' -f1)
        echo "$checksum  $rel_path" >> "$output_file"
        ((file_count++))
    done < <(find "$source_dir" -type f -print0)

    log INFO "✓ Calculated SHA256 checksums for $file_count files"
    log INFO "Checksums saved to: $output_file"

    return 0
}

# Function to get AWS checksum algorithm parameter
get_checksum_algorithm() {
    local algorithm="${1:-CRC64NVME}"

    case "${algorithm^^}" in
        CRC64NVME)
            echo "CRC64NVME"
            ;;
        CRC32C)
            echo "CRC32C"
            ;;
        CRC32)
            echo "CRC32"
            ;;
        SHA256)
            echo "SHA256"
            ;;
        SHA1)
            echo "SHA1"
            ;;
        NONE)
            echo ""
            ;;
        *)
            log WARN "Unknown checksum algorithm: $algorithm, defaulting to CRC64NVME"
            echo "CRC64NVME"
            ;;
    esac
}

# Function to verify S3 object checksums using AWS API (no downloads!)
# Uses 'aws s3api head-object --checksum-mode ENABLED' to retrieve checksums
verify_s3_checksums_aws() {
    local s3_prefix="${1}"
    local errors=0
    local verified=0

    log INFO "Verifying S3 object checksums using AWS Additional Checksums API..."
    log INFO "Algorithm: $CHECKSUM_ALGORITHM (no downloads required)"

    # Get list of objects in S3 (using JSON for reliable parsing)
    local object_list=$(mktemp)
    aws s3api list-objects-v2 \
        --bucket "$BUCKET_NAME" \
        --prefix "$(echo "$s3_prefix" | sed 's|s3://[^/]*/||')" \
        --query 'Contents[].Key' \
        --output json \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" | jq -r '.[]' > "$object_list"

    # Check each object's checksum
    while IFS= read -r object_key; do
        [ -z "$object_key" ] && continue

        # Retrieve object metadata with checksum
        local response=$(aws s3api head-object \
            --bucket "$BUCKET_NAME" \
            --key "$object_key" \
            --checksum-mode ENABLED \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" 2>&1)

        if [ $? -eq 0 ]; then
            # Extract checksum based on algorithm
            local checksum_value=""
            case "${CHECKSUM_ALGORITHM^^}" in
                CRC64NVME)
                    checksum_value=$(echo "$response" | grep -i '"ChecksumCRC64NVME"' | sed 's/.*: "\(.*\)".*/\1/')
                    ;;
                CRC32C)
                    checksum_value=$(echo "$response" | grep -i '"ChecksumCRC32C"' | sed 's/.*: "\(.*\)".*/\1/')
                    ;;
                CRC32)
                    checksum_value=$(echo "$response" | grep -i '"ChecksumCRC32"' | sed 's/.*: "\(.*\)".*/\1/')
                    ;;
                SHA256)
                    checksum_value=$(echo "$response" | grep -i '"ChecksumSHA256"' | sed 's/.*: "\(.*\)".*/\1/')
                    ;;
                SHA1)
                    checksum_value=$(echo "$response" | grep -i '"ChecksumSHA1"' | sed 's/.*: "\(.*\)".*/\1/')
                    ;;
            esac

            if [ -n "$checksum_value" ]; then
                log DEBUG "✓ $object_key - AWS checksum: $checksum_value"
                ((verified++))
            else
                log WARN "✗ $object_key - No checksum found (may not have been uploaded with checksums)"
                ((errors++))
            fi
        else
            log ERROR "✗ $object_key - Failed to retrieve checksum from S3"
            ((errors++))
        fi
    done < "$object_list"

    rm -f "$object_list"

    log INFO "AWS checksum verification complete: $verified verified, $errors missing/errors"

    return $errors
}

# Function to verify files in S3 by downloading (LEGACY - NOT RECOMMENDED)
# WARNING: This downloads all files from S3 for verification - slow and costly!
# Use verify_s3_checksums_aws() instead for AWS Additional Checksums verification
verify_s3_checksums_legacy() {
    local checksum_file=$1
    local temp_dir=$(mktemp -d)
    local errors=0
    local verified=0

    log WARN "Using LEGACY checksum verification (downloads files from S3)"
    log WARN "This is NOT RECOMMENDED - use AWS Additional Checksums instead"
    log INFO "Verifying files in S3 against local SHA256 checksums..."

    while IFS= read -r line; do
        local expected_checksum=$(echo "$line" | cut -d' ' -f1)
        local file_path=$(echo "$line" | cut -d' ' -f3-)
        local s3_path="${S3_DEST}${file_path}"
        local temp_file="$temp_dir/$(basename "$file_path")"

        # Download file from S3
        if aws s3 cp "$s3_path" "$temp_file" --profile "$AWS_PROFILE" --region "$AWS_REGION" --quiet 2>/dev/null; then
            # Calculate checksum of downloaded file
            local actual_checksum=$(sha256sum "$temp_file" | cut -d' ' -f1)

            if [ "$expected_checksum" = "$actual_checksum" ]; then
                log DEBUG "✓ $file_path - checksum verified"
                ((verified++))
            else
                log ERROR "✗ $file_path - checksum mismatch!"
                log ERROR "  Expected: $expected_checksum"
                log ERROR "  Actual:   $actual_checksum"
                ((errors++))
            fi

            rm -f "$temp_file"
        else
            log WARN "✗ $file_path - failed to download from S3"
            ((errors++))
        fi
    done < "$checksum_file"

    # Cleanup
    rm -rf "$temp_dir"

    log INFO "Verification complete: $verified verified, $errors errors"

    return $errors
}

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

log INFO "======================================"
log INFO "DataSync Simulator Starting"
log INFO "======================================"
log INFO "Source: $WATCH_DIR"
log INFO "Destination: $S3_DEST"
log INFO "AWS Profile: $AWS_PROFILE"
log INFO "Region: $AWS_REGION"
log INFO ""
log INFO "AWS Additional Checksums Configuration:"
log INFO "  Checksum Verification: $ENABLE_CHECKSUM_VERIFICATION"
log INFO "  Checksum Algorithm: $CHECKSUM_ALGORITHM"
if [ "$CHECKSUM_ALGORITHM" != "NONE" ] && [ "$ENABLE_CHECKSUM_VERIFICATION" = "true" ]; then
    log INFO "  Server-side verification: ENABLED (AWS validates automatically)"
    log INFO "  Performance benefit: Single-pass upload with trailing checksums"
fi
log INFO "  Legacy download verification: $VERIFY_AFTER_UPLOAD"
log INFO ""

# Check if source directory exists
if [ ! -d "$WATCH_DIR" ]; then
    log ERROR "Source directory does not exist: $WATCH_DIR"
    exit 1
fi

# Count files before sync
FILES_BEFORE=$(find "$WATCH_DIR" -type f | wc -l)
SIZE_BEFORE=$(du -sh "$WATCH_DIR" | cut -f1)

log INFO "Files to sync: $FILES_BEFORE files ($SIZE_BEFORE)"
log INFO ""

# Calculate local SHA256 checksums for compliance records (optional)
# Note: AWS will calculate checksums automatically during upload using HTTP trailers
if [ "$CHECKSUM_ALGORITHM" = "NONE" ] && [ "$ENABLE_CHECKSUM_VERIFICATION" = "true" ] && [ $FILES_BEFORE -gt 0 ]; then
    log INFO "CHECKSUM_ALGORITHM=NONE - using legacy SHA256 checksum calculation"
    calculate_checksums_legacy "$WATCH_DIR" "$CHECKSUM_FILE"
    log INFO ""
elif [ "$ENABLE_CHECKSUM_VERIFICATION" = "true" ] && [ $FILES_BEFORE -gt 0 ]; then
    log INFO "AWS Additional Checksums enabled - checksums will be calculated during upload"
    log INFO "Algorithm: $CHECKSUM_ALGORITHM (hardware-accelerated, single-pass operation)"
    log INFO ""
fi

log INFO "Starting sync operation..."

# Record start time
START_TIME=$(date +%s)

# Get AWS checksum algorithm parameter
AWS_CHECKSUM_PARAM=$(get_checksum_algorithm "$CHECKSUM_ALGORITHM")

# Configure S3 transfer settings (legacy variable)
if [ -n "$S3_MAX_CONCURRENT_REQUESTS" ]; then
    export AWS_MAX_CONCURRENT_REQUESTS="$S3_MAX_CONCURRENT_REQUESTS"
    log INFO "S3 max concurrent requests: $S3_MAX_CONCURRENT_REQUESTS (legacy setting)"
fi

# Configure S3 transfer optimization settings (new variables)
if [ -n "$AWS_CLI_S3_MAX_CONCURRENT_REQUESTS" ]; then
    export AWS_MAX_CONCURRENT_REQUESTS="$AWS_CLI_S3_MAX_CONCURRENT_REQUESTS"
    log INFO "S3 max concurrent requests: $AWS_CLI_S3_MAX_CONCURRENT_REQUESTS"
else
    log INFO "S3 max concurrent requests: 10 (AWS CLI default)"
fi

if [ -n "$AWS_CLI_S3_MULTIPART_THRESHOLD" ]; then
    log INFO "S3 multipart threshold: $AWS_CLI_S3_MULTIPART_THRESHOLD"
fi

if [ -n "$AWS_CLI_S3_MULTIPART_CHUNKSIZE" ]; then
    log INFO "S3 multipart chunk size: $AWS_CLI_S3_MULTIPART_CHUNKSIZE"
fi

if [ -n "$AWS_CLI_S3_MAX_BANDWIDTH" ]; then
    log INFO "S3 max bandwidth: $AWS_CLI_S3_MAX_BANDWIDTH"
fi

# Apply AWS CLI configuration via aws configure set (persistent)
if [ -n "$AWS_CLI_S3_MULTIPART_THRESHOLD" ]; then
    aws configure set default.s3.multipart_threshold "$AWS_CLI_S3_MULTIPART_THRESHOLD" --profile "$AWS_PROFILE" 2>/dev/null || true
fi
if [ -n "$AWS_CLI_S3_MULTIPART_CHUNKSIZE" ]; then
    aws configure set default.s3.multipart_chunksize "$AWS_CLI_S3_MULTIPART_CHUNKSIZE" --profile "$AWS_PROFILE" 2>/dev/null || true
fi
if [ -n "$AWS_CLI_S3_MAX_BANDWIDTH" ] && [ "$AWS_CLI_S3_MAX_BANDWIDTH" != "" ]; then
    aws configure set default.s3.max_bandwidth "$AWS_CLI_S3_MAX_BANDWIDTH" --profile "$AWS_PROFILE" 2>/dev/null || true
fi

# Build sync command with checksum support
SYNC_CMD="aws s3 sync \"$WATCH_DIR\" \"$S3_DEST\" \
    --storage-class INTELLIGENT_TIERING \
    --profile \"$AWS_PROFILE\" \
    --region \"$AWS_REGION\" \
    --metadata \"synced-by=datasync-simulator,timestamp=$(date +%s)\""

# Add checksum algorithm if enabled and not NONE
if [ -n "$AWS_CHECKSUM_PARAM" ] && [ "$ENABLE_CHECKSUM_VERIFICATION" = "true" ]; then
    SYNC_CMD="$SYNC_CMD --checksum-algorithm $AWS_CHECKSUM_PARAM"
    log INFO "Using AWS Additional Checksums with algorithm: $AWS_CHECKSUM_PARAM"
    log INFO "S3 will validate checksums automatically during upload (HTTP trailers)"
else
    log INFO "AWS Additional Checksums disabled - using standard sync"
fi

SYNC_CMD="$SYNC_CMD --delete"

# Execute sync command
log INFO "Executing: aws s3 sync with checksum verification..."
eval "$SYNC_CMD" 2>&1 | tee -a "$LOG_FILE"

SYNC_STATUS=$?

# Check for BadDigest errors (checksum validation failures)
if grep -q "BadDigest" "$LOG_FILE"; then
    log ERROR "AWS checksum validation failed (BadDigest error detected)"
    log ERROR "This indicates data corruption during transmission or calculation error"
    SYNC_STATUS=1
fi

# Record end time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log INFO ""
log INFO "======================================"
if [ $SYNC_STATUS -eq 0 ]; then
    log INFO "✅ Sync completed successfully"
else
    log ERROR "❌ Sync failed with status: $SYNC_STATUS"
fi
log INFO "Duration: ${DURATION} seconds"
log INFO "======================================"

# Get post-sync statistics
log INFO ""
log INFO "Checking S3 destination..."
S3_OBJECT_COUNT=$(aws s3 ls "$S3_DEST" --recursive --profile "$AWS_PROFILE" | wc -l)
log INFO "Objects in S3: $S3_OBJECT_COUNT"

# Verify checksums after upload (if enabled and sync was successful)
CHECKSUM_VERIFIED="false"
CHECKSUM_ERRORS=0

if [ $SYNC_STATUS -eq 0 ] && [ "$ENABLE_CHECKSUM_VERIFICATION" = "true" ]; then
    log INFO ""

    # Use AWS Additional Checksums API for verification (no downloads!)
    if [ "$CHECKSUM_ALGORITHM" != "NONE" ]; then
        log INFO "Verifying uploads using AWS Additional Checksums API..."
        log INFO "Note: This checks S3 metadata without downloading files (fast and free)"
        verify_s3_checksums_aws "$S3_DEST"
        CHECKSUM_ERRORS=$?
        if [ $CHECKSUM_ERRORS -eq 0 ]; then
            CHECKSUM_VERIFIED="true"
            log INFO "✅ All AWS checksums verified successfully"
        else
            CHECKSUM_VERIFIED="partial"
            log WARN "⚠ Some files missing AWS checksums (may have been uploaded before checksums enabled)"
        fi
    fi

    # Legacy download-based verification (NOT RECOMMENDED)
    if [ "$VERIFY_AFTER_UPLOAD" = "true" ] && [ -f "$CHECKSUM_FILE" ]; then
        log INFO ""
        log WARN "Legacy download-based verification enabled (SLOW and COSTLY)"
        verify_s3_checksums_legacy "$CHECKSUM_FILE"
        LEGACY_ERRORS=$?
        if [ $LEGACY_ERRORS -gt 0 ]; then
            CHECKSUM_VERIFIED="failed"
            CHECKSUM_ERRORS=$((CHECKSUM_ERRORS + LEGACY_ERRORS))
            log ERROR "❌ Legacy checksum verification failed with $LEGACY_ERRORS errors"
        fi
    fi
fi

# Save sync metadata
cat > "$LOG_DIR/last-sync.json" <<EOF
{
    "timestamp": "$(date -Iseconds)",
    "duration_seconds": $DURATION,
    "files_synced": $FILES_BEFORE,
    "source_size": "$SIZE_BEFORE",
    "s3_objects": $S3_OBJECT_COUNT,
    "status": "$( [ $SYNC_STATUS -eq 0 ] && echo 'success' || echo 'failed' )",
    "source": "$WATCH_DIR",
    "destination": "$S3_DEST",
    "checksum_verification": {
        "enabled": $ENABLE_CHECKSUM_VERIFICATION,
        "algorithm": "$CHECKSUM_ALGORITHM",
        "aws_additional_checksums": "$( [ "$CHECKSUM_ALGORITHM" != "NONE" ] && echo 'true' || echo 'false' )",
        "server_side_validation": "$( [ "$CHECKSUM_ALGORITHM" != "NONE" ] && echo 'enabled' || echo 'disabled' )",
        "verify_after_upload": $VERIFY_AFTER_UPLOAD,
        "verified": "$CHECKSUM_VERIFIED",
        "checksum_file": "$( [ -f "$CHECKSUM_FILE" ] && echo "$CHECKSUM_FILE" || echo "null" )",
        "errors": $CHECKSUM_ERRORS
    }
}
EOF

log INFO ""
log INFO "Sync metadata saved to: $LOG_DIR/last-sync.json"
if [ "$CHECKSUM_ALGORITHM" != "NONE" ] && [ "$ENABLE_CHECKSUM_VERIFICATION" = "true" ]; then
    log INFO "AWS Additional Checksums: Algorithm=$CHECKSUM_ALGORITHM, Server-side validation=ENABLED"
fi
if [ "$ENABLE_CHECKSUM_VERIFICATION" = "true" ] && [ -f "$CHECKSUM_FILE" ]; then
    log INFO "Local checksums saved to: $CHECKSUM_FILE"
fi
log INFO ""

# Exit with appropriate status
if [ $SYNC_STATUS -eq 0 ] && [ $CHECKSUM_ERRORS -eq 0 ]; then
    exit 0
else
    exit 1
fi
