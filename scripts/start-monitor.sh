#!/bin/bash
# Start the hot folder monitor

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_SCRIPT="$SCRIPT_DIR/hotfolder-monitor.sh"

# Check if already running
if pgrep -f "hotfolder-monitor.sh" > /dev/null; then
    echo "⚠️  Monitor is already running"
    echo ""
    echo "To stop it, run: ./stop-monitor.sh"
    echo "To check status, run: ./check-status.sh"
    exit 1
fi

echo "Starting hot folder monitor..."
echo ""

# Start monitor in background
nohup bash "$MONITOR_SCRIPT" > /dev/null 2>&1 &
MONITOR_PID=$!

sleep 2

if ps -p $MONITOR_PID > /dev/null; then
    echo "✅ Monitor started successfully (PID: $MONITOR_PID)"
    echo ""
    echo "The monitor is now watching for file changes and will"
    echo "automatically sync to S3 when files are added/modified."
    echo ""
    echo "Commands:"
    echo "  • Stop monitor:    ./stop-monitor.sh"
    echo "  • Check status:    ./check-status.sh"
    echo "  • View logs:       tail -f ~/datasync-test/logs/monitor-$(date +%Y%m%d).log"
    echo ""
else
    echo "❌ Failed to start monitor"
    exit 1
fi
