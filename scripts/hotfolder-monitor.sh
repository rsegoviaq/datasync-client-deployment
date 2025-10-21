#!/bin/bash
# Hot Folder Monitor - Watches for file changes and triggers sync
# Simulates DataSync hot folder behavior

# Load configuration
if [ -f ~/datasync-config.env ]; then
    source ~/datasync-config.env
else
    echo "❌ Configuration file not found: ~/datasync-config.env"
    exit 1
fi

# Configuration
WATCH_DIR="${SOURCE_DIR:-$HOME/datasync-test/source}"
CHECK_INTERVAL=30  # Check every 30 seconds
LOG_FILE="$LOGS_DIR/monitor-$(date +%Y%m%d).log"
SYNC_SCRIPT="$SCRIPTS_DIR/datasync-simulator.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check if sync is already running
is_sync_running() {
    pgrep -f "datasync-simulator.sh" > /dev/null
    return $?
}

# Main monitoring function
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        Hot Folder Monitor - DataSync Simulator            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
log "Monitor started"
log "Watching directory: $WATCH_DIR"
log "Check interval: ${CHECK_INTERVAL} seconds"
log "Sync script: $SYNC_SCRIPT"
echo ""

# Store initial state
LAST_MOD_TIME=$(find "$WATCH_DIR" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1)
LAST_FILE_COUNT=$(find "$WATCH_DIR" -type f 2>/dev/null | wc -l)

while true; do
    # Get current state
    CURRENT_MOD_TIME=$(find "$WATCH_DIR" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1)
    CURRENT_FILE_COUNT=$(find "$WATCH_DIR" -type f 2>/dev/null | wc -l)

    # Check for changes
    if [ "$CURRENT_MOD_TIME" != "$LAST_MOD_TIME" ] || [ "$CURRENT_FILE_COUNT" != "$LAST_FILE_COUNT" ]; then

        TOTAL_SIZE=$(du -sh "$WATCH_DIR" 2>/dev/null | cut -f1)

        echo -e "${YELLOW}⚡ Changes detected!${NC}"
        log "Changes detected in $WATCH_DIR"
        log "  Files: $CURRENT_FILE_COUNT (was: $LAST_FILE_COUNT)"
        log "  Total size: $TOTAL_SIZE"

        # Check if sync is already running
        if is_sync_running; then
            echo -e "${CYAN}⏳ Sync already in progress, waiting...${NC}"
            log "Sync already running, skipping this cycle"
        else
            echo -e "${GREEN}📤 Triggering sync...${NC}"
            log "Starting sync operation"

            # Run sync script
            bash "$SYNC_SCRIPT"
            SYNC_EXIT_CODE=$?

            if [ $SYNC_EXIT_CODE -eq 0 ]; then
                echo -e "${GREEN}✅ Sync completed successfully${NC}"
                log "Sync completed successfully"
            else
                echo -e "${RED}❌ Sync failed with exit code: $SYNC_EXIT_CODE${NC}"
                log "Sync failed with exit code: $SYNC_EXIT_CODE"
            fi
        fi

        # Update last known state
        LAST_MOD_TIME=$CURRENT_MOD_TIME
        LAST_FILE_COUNT=$CURRENT_FILE_COUNT

    else
        echo -e "${CYAN}👁️  No changes (Files: $CURRENT_FILE_COUNT, Size: $(du -sh "$WATCH_DIR" 2>/dev/null | cut -f1))${NC}"
        log "No changes detected"
    fi

    echo ""
    sleep $CHECK_INTERVAL
done
