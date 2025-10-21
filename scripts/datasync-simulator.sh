#!/bin/bash
# DataSync Simulator using AWS S3 Sync
# Simulates DataSync behavior for local testing with checksum verification

# Load configuration
if [ -f ~/datasync-config.env ]; then
    source ~/datasync-config.env
else
    echo "❌ Configuration file not found: ~/datasync-config.env"
    exit 1
fi

# Script configuration
WATCH_DIR="${SOURCE_DIR:-$HOME/datasync-test/source}"
S3_DEST="s3://$BUCKET_NAME/datasync-test/"
LOG_DIR="${LOGS_DIR:-$HOME/datasync-test/logs}"
LOG_FILE="$LOG_DIR/sync-$(date +%Y%m%d).log"
CHECKSUM_DIR="$LOG_DIR/checksums"
CHECKSUM_FILE="$CHECKSUM_DIR/checksums-$(date +%Y%m%d-%H%M%S).txt"

# Feature flags
ENABLE_CHECKSUM_VERIFICATION=${ENABLE_CHECKSUM_VERIFICATION:-true}
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

# Function to calculate checksums for all files
calculate_checksums() {
    local source_dir=$1
    local output_file=$2

    log INFO "Calculating SHA256 checksums for all files..."

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

    log INFO "✓ Calculated checksums for $file_count files"
    log INFO "Checksums saved to: $output_file"

    return 0
}

# Function to verify files in S3 against checksums
verify_s3_checksums() {
    local checksum_file=$1
    local temp_dir=$(mktemp -d)
    local errors=0
    local verified=0

    log INFO "Verifying files in S3 against local checksums..."

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
log INFO "Checksum Verification: $ENABLE_CHECKSUM_VERIFICATION"
log INFO "Verify After Upload: $VERIFY_AFTER_UPLOAD"
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

# Calculate checksums before sync (if enabled)
if [ "$ENABLE_CHECKSUM_VERIFICATION" = "true" ] && [ $FILES_BEFORE -gt 0 ]; then
    calculate_checksums "$WATCH_DIR" "$CHECKSUM_FILE"
    log INFO ""
fi

log INFO "Starting sync operation..."

# Record start time
START_TIME=$(date +%s)

# Perform sync with detailed logging
aws s3 sync "$WATCH_DIR" "$S3_DEST" \
    --storage-class INTELLIGENT_TIERING \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --metadata "synced-by=datasync-simulator,timestamp=$(date +%s)" \
    --delete \
    2>&1 | tee -a "$LOG_FILE"

SYNC_STATUS=$?

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
if [ "$VERIFY_AFTER_UPLOAD" = "true" ] && [ $SYNC_STATUS -eq 0 ] && [ "$ENABLE_CHECKSUM_VERIFICATION" = "true" ] && [ -f "$CHECKSUM_FILE" ]; then
    log INFO ""
    verify_s3_checksums "$CHECKSUM_FILE"
    CHECKSUM_ERRORS=$?
    if [ $CHECKSUM_ERRORS -eq 0 ]; then
        CHECKSUM_VERIFIED="true"
        log INFO "✅ All checksums verified successfully"
    else
        CHECKSUM_VERIFIED="failed"
        log ERROR "❌ Checksum verification failed with $CHECKSUM_ERRORS errors"
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
        "verify_after_upload": $VERIFY_AFTER_UPLOAD,
        "verified": "$CHECKSUM_VERIFIED",
        "checksum_file": "$( [ -f "$CHECKSUM_FILE" ] && echo "$CHECKSUM_FILE" || echo "null" )",
        "errors": $CHECKSUM_ERRORS
    }
}
EOF

log INFO ""
log INFO "Sync metadata saved to: $LOG_DIR/last-sync.json"
if [ "$ENABLE_CHECKSUM_VERIFICATION" = "true" ] && [ -f "$CHECKSUM_FILE" ]; then
    log INFO "Checksums saved to: $CHECKSUM_FILE"
fi
log INFO ""

# Exit with appropriate status
if [ $SYNC_STATUS -eq 0 ] && [ $CHECKSUM_ERRORS -eq 0 ]; then
    exit 0
else
    exit 1
fi
