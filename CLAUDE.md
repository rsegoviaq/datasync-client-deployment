# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an AWS DataSync deployment kit that provides a hybrid migration approach for file synchronization from on-premise locations to AWS S3. The system starts with a cost-effective simulator mode (~$2-5/month) and provides a migration path to the full AWS DataSync agent when needed (~$220-265/month).

**Two Deployment Modes:**
- **Simulator Mode**: AWS CLI-based sync using `aws s3 sync` with SHA256 checksum verification
- **Agent Mode**: Full AWS DataSync agent with enterprise features (migration target)

## Key Architecture Concepts

### Configuration System
All client deployments use a centralized configuration file (`~/datasync-config.env`) generated from `config/config-template.env`. This file contains:
- AWS credentials and profile settings
- S3 bucket configuration
- Local directory paths
- Checksum verification flags (`ENABLE_CHECKSUM_VERIFICATION`, `VERIFY_AFTER_UPLOAD`)
- Monitoring settings
- Migration status tracking (`DEPLOYMENT_MODE`: "simulator" | "agent" | "parallel")

All operational scripts source this configuration file at startup and fail gracefully if not found.

### Core Scripts Flow

1. **setup-client.sh** - Interactive wizard that:
   - Validates AWS prerequisites (aws-cli, jq, sed, sha256sum)
   - Creates AWS resources (S3 bucket with versioning, IAM roles, CloudWatch log groups)
   - Generates client-specific configuration from template
   - Creates deployment package in `packages/[client]-deployment.tar.gz`

2. **datasync-simulator.sh** - Core sync engine that:
   - Calculates SHA256 checksums before upload
   - Performs `aws s3 sync` with intelligent-tiering storage class
   - Optionally verifies checksums after upload (downloads files to compare)
   - Logs all operations with timestamps
   - Saves checksums to `$LOGS_DIR/checksums/checksums-*.txt`

3. **hotfolder-monitor.sh** - Change detection daemon that:
   - Polls source directory every 30 seconds (configurable via `MONITOR_CHECK_INTERVAL`)
   - Detects file modifications and count changes using `find` timestamps
   - Triggers sync only if not already running (checks via `pgrep`)
   - Runs as background process

4. **Migration scripts** (migration/):
   - `prepare-migration.sh` - Validates system requirements (8 CPU cores, 48GB RAM, 200GB disk)
   - `cutover-to-datasync.sh` - Provisions DataSync agent and performs cutover

### State Management

The system tracks state through:
- **Deployment mode**: Set via `DEPLOYMENT_MODE` in config (simulator/agent/parallel)
- **Monitor state**: Background process tracked via PID file
- **Sync state**: Detected via `pgrep -f "datasync-simulator.sh"`
- **Checksums**: Historical record in `$LOGS_DIR/checksums/`
- **Logs**: Daily rotation pattern `sync-YYYYMMDD.log`, `monitor-YYYYMMDD.log`

### AWS Resource Naming Conventions

Resources are created with consistent naming:
- S3 Bucket: `datasync-[client]-[timestamp]`
- IAM Role: `DataSync-[client]-Role`
- CloudWatch Log Group: `/aws/datasync/[client]`
- All resources tagged with `Project=[client]` and `Environment=[env]`

## Common Development Commands

### Setup New Client
```bash
./setup-client.sh [client-name]
# Follow interactive prompts for:
# - Client contact information
# - AWS region selection
# - S3 bucket configuration
# - Checksum verification preferences
# - Alert email configuration
```

### Test Simulator Locally
```bash
# Load config
source ~/datasync-config.env

# Run single sync
cd $SCRIPTS_DIR
./sync-now.sh

# Start monitoring
./start-monitor.sh

# Check status
./check-status.sh

# Verify checksums
./verify-checksums.sh

# Stop monitoring
./stop-monitor.sh
```

### Validate Migration Readiness
```bash
cd migration/
./prepare-migration.sh
# Reviews: system requirements, transfer metrics, cost analysis, compliance needs
```

### Test Package Generation
```bash
# The setup creates a package at:
packages/[client]-deployment.tar.gz

# Package contents:
# - Client-specific config file
# - All operational scripts
# - Installation script
# - Documentation
```

## Critical Implementation Details

### Checksum Verification System
- Pre-upload: Always calculated for audit trail
- Post-upload: Optional (controlled by `VERIFY_AFTER_UPLOAD` flag)
- **WARNING**: Post-upload verification downloads ALL files from S3 - expensive for large datasets
- Checksums stored with timestamps for compliance auditing
- Format: `[SHA256]  [relative_path]` (compatible with sha256sum -c)

### Error Handling Pattern
All scripts follow this pattern:
```bash
set -e  # Exit on error for setup scripts
# OR manual error checking for operational scripts

if [ -f ~/datasync-config.env ]; then
    source ~/datasync-config.env
else
    echo "❌ Configuration file not found"
    exit 1
fi
```

### AWS Profile Requirement
All AWS CLI commands MUST use `--profile "$AWS_PROFILE"` to support multiple client configurations on same machine.

### Sync Locking Mechanism
Only one sync can run at a time, enforced by:
- Monitor checks `pgrep -f "datasync-simulator.sh"`
- No PID file or flock used - relies on process name matching

## File Locations

When working on this codebase:

- **Operational scripts**: `scripts/` - All executable, must maintain shebang `#!/bin/bash`
- **Configuration**: `config/config-template.env` - Template with `[PLACEHOLDER]` markers
- **Setup wizard**: `setup-client.sh` - Root level, orchestrates everything
- **Migration tools**: `migration/` - Two-step process (prepare → cutover)
- **Documentation**: `docs/` - User-facing guides (DEPLOYMENT_GUIDE.md, SIMULATOR_VS_AGENT.md)
- **Generated packages**: `packages/` - Created during setup, gitignored

## Testing Approach

Since this is a deployment kit:
1. Test with mock AWS credentials using `--dryrun` where possible
2. Validate package generation without executing AWS API calls
3. Test scripts source configuration correctly with missing config
4. Verify templating system replaces all `[PLACEHOLDER]` values
5. Check error messages are user-friendly (non-technical client users)

## Migration Path Understanding

The system is designed for gradual adoption:
1. **Phase 1**: Deploy simulator mode (hours to setup)
2. **Phase 2**: Monitor metrics for 2-4 weeks
3. **Phase 3**: Run migration readiness assessment
4. **Phase 4**: Decision point based on volume/performance/cost
5. **Phase 5**: If needed, deploy agent in parallel mode
6. **Phase 6**: Cutover and decommission simulator

The `DEPLOYMENT_MODE` config flag enables parallel testing of both modes before cutover.

## Color Output Convention

All user-facing scripts use consistent color coding:
- GREEN: Success messages
- YELLOW: Warnings/cautions
- RED: Errors/failures
- BLUE: Informational headers
- CYAN: Prompts/questions

Colors defined as: `GREEN='\033[0;32m'` etc., with `NC='\033[0m'` reset.

## Important Constraints

- **No Docker/containers**: Direct host installation for client simplicity
- **Bash 4+**: Uses arrays and modern bash features
- **Linux/macOS**: Uses GNU coreutils (`sha256sum`, `find -printf`)
- **AWS CLI v2**: Required for S3 intelligent-tiering support
- **No external dependencies**: Only aws-cli, jq, sed, sha256sum (validated at startup)

## Configuration File Lifecycle

1. **Template**: `config/config-template.env` (version controlled)
2. **Generated**: During `setup-client.sh` execution (replaces placeholders)
3. **Packaged**: Included in `.tar.gz` as `datasync-config.env`
4. **Installed**: Copied to `~/datasync-config.env` on client machine
5. **Loaded**: Sourced by all operational scripts at runtime

Never modify the installed config manually - regenerate via setup-client.sh for consistency.
