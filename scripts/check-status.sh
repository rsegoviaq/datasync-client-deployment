#!/bin/bash
# Check status of DataSync simulation

source ~/datasync-config.env

echo "╔════════════════════════════════════════════════════════════╗"
echo "║         DataSync Simulation - Status Check                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check monitor status
if pgrep -f "hotfolder-monitor.sh" > /dev/null; then
    MONITOR_PID=$(pgrep -f "hotfolder-monitor.sh")
    echo "✅ Monitor: RUNNING (PID: $MONITOR_PID)"
else
    echo "❌ Monitor: STOPPED"
fi

# Check sync status
if pgrep -f "datasync-simulator.sh" > /dev/null; then
    echo "⏳ Sync: IN PROGRESS"
else
    echo "✓  Sync: IDLE"
fi

echo ""
echo "Local Source:"
echo "──────────────"
if [ -d "$SOURCE_DIR" ]; then
    FILE_COUNT=$(find "$SOURCE_DIR" -type f 2>/dev/null | wc -l)
    TOTAL_SIZE=$(du -sh "$SOURCE_DIR" 2>/dev/null | cut -f1)
    echo "  Location: $SOURCE_DIR"
    echo "  Files: $FILE_COUNT"
    echo "  Size: $TOTAL_SIZE"
else
    echo "  ⚠️  Directory not found: $SOURCE_DIR"
fi

echo ""
echo "S3 Destination:"
echo "──────────────"
S3_PATH="s3://$BUCKET_NAME/datasync-test/"
S3_COUNT=$(aws s3 ls "$S3_PATH" --recursive --profile "$AWS_PROFILE" 2>/dev/null | wc -l)
echo "  Bucket: $BUCKET_NAME"
echo "  Path: datasync-test/"
echo "  Objects: $S3_COUNT"

echo ""
echo "Last Sync:"
echo "──────────────"
if [ -f "$LOGS_DIR/last-sync.json" ]; then
    LAST_SYNC_TIME=$(jq -r '.timestamp' "$LOGS_DIR/last-sync.json" 2>/dev/null)
    LAST_SYNC_STATUS=$(jq -r '.status' "$LOGS_DIR/last-sync.json" 2>/dev/null)
    LAST_SYNC_DURATION=$(jq -r '.duration_seconds' "$LOGS_DIR/last-sync.json" 2>/dev/null)

    echo "  Time: $LAST_SYNC_TIME"
    echo "  Status: $LAST_SYNC_STATUS"
    echo "  Duration: ${LAST_SYNC_DURATION}s"
else
    echo "  No sync performed yet"
fi

echo ""
echo "Logs:"
echo "──────────────"
echo "  Monitor log: $LOGS_DIR/monitor-$(date +%Y%m%d).log"
echo "  Sync log: $LOGS_DIR/sync-$(date +%Y%m%d).log"
echo ""
