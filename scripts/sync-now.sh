#!/bin/bash
# Manually trigger a sync operation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/datasync-simulator.sh"

echo "╔════════════════════════════════════════════════════════════╗"
echo "║           Manual Sync Trigger                             ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check if sync is already running
if pgrep -f "datasync-simulator.sh" > /dev/null; then
    echo "⚠️  Sync is already in progress"
    echo "Wait for it to complete or check status with: ./check-status.sh"
    exit 1
fi

echo "Starting sync operation..."
echo ""

bash "$SYNC_SCRIPT"
EXIT_CODE=$?

echo ""
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Sync completed successfully"
else
    echo "❌ Sync failed with exit code: $EXIT_CODE"
fi

exit $EXIT_CODE
