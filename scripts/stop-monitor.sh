#!/bin/bash
# Stop the hot folder monitor

echo "Stopping hot folder monitor..."

if pgrep -f "hotfolder-monitor.sh" > /dev/null; then
    pkill -f "hotfolder-monitor.sh"
    sleep 1

    if pgrep -f "hotfolder-monitor.sh" > /dev/null; then
        echo "❌ Failed to stop monitor (still running)"
        exit 1
    else
        echo "✅ Monitor stopped successfully"
    fi
else
    echo "⚠️  Monitor is not running"
fi
