# DataSync Client Deployment Guide

**Version**: 1.0
**Last Updated**: October 2025
**Deployment Mode**: Simulator (with migration path to Full Agent)

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Deployment Process](#deployment-process)
4. [Post-Deployment](#post-deployment)
5. [Client Training](#client-training)
6. [Troubleshooting](#troubleshooting)

---

## Overview

This guide walks you through deploying the DataSync simulator to a client site. The entire process typically takes 1-2 hours.

### What Gets Deployed

- ✅ AWS S3 bucket (client-specific)
- ✅ IAM roles for DataSync access
- ✅ CloudWatch logging
- ✅ Local sync scripts with checksum verification
- ✅ Hot folder monitoring
- ✅ Configuration files
- ✅ Email alerts (optional)

### Deployment Modes

| Mode | Use Case | Cost | Setup Time |
|------|----------|------|------------|
| **Simulator** | Start here | $2-5/mo | 1-2 hours |
| **Full Agent** | Migrate later | $220-265/mo | 1-2 days |

---

## Prerequisites

### On Your Machine (Setup Side)

✅ **Required Software:**
- AWS CLI 2.x (`aws --version`)
- jq (`jq --version`)
- Git (for version control)
- Bash shell (Linux/Mac/WSL2)

✅ **AWS Access:**
- Valid AWS credentials configured
- Permissions for: S3, IAM, DataSync, CloudWatch, SNS
- Account ID known

✅ **Client Information:**
- Client name
- Contact person name and email
- Desired AWS region (default: us-east-1)

### On Client Machine (Deployment Target)

✅ **Required:**
- AWS CLI 2.x installed
- Linux, macOS, or Windows with WSL2
- Bash shell
- Internet connectivity
- 10GB+ free disk space

✅ **Optional but Recommended:**
- Dedicated user account for DataSync
- Email account for alerts
- Monitoring dashboard access

---

## Deployment Process

### Phase 1: Setup (Your Side) - 30 minutes

#### Step 1.1: Run Setup Wizard

```bash
cd ~/datasync-client-deployment
./setup-client.sh acme-corp
```

The wizard will ask for:
1. Client name (e.g., "acme-corp")
2. Primary contact name
3. Contact email
4. AWS profile to use
5. AWS region
6. S3 bucket name (auto-suggested)
7. Local directories
8. Monitoring preferences
9. Email alerts (optional)
10. Checksum settings

**Example Session:**

```
===============================================================================
DataSync Client Setup Wizard
===============================================================================

Client name: acme-corp
Primary contact name: John Doe
Contact email: john.doe@acmecorp.com
AWS profile name [default]: datasync-test

Testing AWS credentials...
✓ AWS credentials valid
Account ID: 016495285575

AWS region [us-east-1]: us-east-1
S3 bucket name [datasync-acme-corp-20251016]:
S3 subdirectory [datasync]: uploads

DataSync home directory [/home/user/datasync-acme-corp]:

Configure email alerts? [Y/n]: y
Alert email address [john.doe@acmecorp.com]:

Enable checksum verification? [Y/n]: y
Enable automatic post-upload verification? [y/N]: n
```

#### Step 1.2: Review Configuration

The wizard creates:
- Configuration file: `config/acme-corp-config.env`
- Deployment package: `packages/acme-corp-deployment.tar.gz`

Review the configuration:

```bash
cat config/acme-corp-config.env
```

#### Step 1.3: Verify AWS Infrastructure

The wizard automatically creates:
- ✅ S3 bucket with encryption and versioning
- ✅ IAM role for DataSync
- ✅ CloudWatch log group
- ✅ SNS topic for alerts (if enabled)

Verify in AWS Console or:

```bash
# Check S3 bucket
aws s3 ls s3://datasync-acme-corp-20251016

# Check IAM role
aws iam get-role --role-name DataSyncRole-acme-corp

# Check log group
aws logs describe-log-groups --log-group-name-prefix /aws/datasync/acme-corp
```

---

### Phase 2: Transfer to Client - 15 minutes

#### Step 2.1: Package Transfer

Transfer the deployment package to client:

**Option A: Via SCP/SFTP**
```bash
scp packages/acme-corp-deployment.tar.gz client@client-server.com:~/
```

**Option B: Via Cloud Storage**
```bash
# Upload to S3 (temporary)
aws s3 cp packages/acme-corp-deployment.tar.gz s3://temp-transfer-bucket/

# Client downloads
aws s3 cp s3://temp-transfer-bucket/acme-corp-deployment.tar.gz ~/
```

**Option C: Via USB/Physical Media**
```bash
# Copy to USB drive
cp packages/acme-corp-deployment.tar.gz /media/usb/
```

#### Step 2.2: Pre-Installation Checks (Client Side)

On the client machine:

```bash
# Check AWS CLI
aws --version
# Expected: aws-cli/2.x.x

# Check disk space
df -h ~
# Need: 10GB+ free

# Check internet connectivity
ping -c 3 s3.amazonaws.com
```

---

### Phase 3: Installation (Client Side) - 30 minutes

#### Step 3.1: Extract Package

```bash
cd ~
tar -xzf acme-corp-deployment.tar.gz
cd acme-corp-deployment
ls -la
```

You should see:
```
.
├── install.sh
├── README.md
├── config/
│   └── datasync-config.env
├── docs/
│   └── [documentation files]
└── scripts/
    └── [operational scripts]
```

#### Step 3.2: Configure AWS Credentials

```bash
# Configure AWS CLI
aws configure --profile datasync-acme-corp

# Enter when prompted:
#   AWS Access Key ID: [provided by you]
#   AWS Secret Access Key: [provided by you]
#   Default region: us-east-1
#   Default output format: json

# Test credentials
aws sts get-caller-identity --profile datasync-acme-corp
```

Expected output:
```json
{
    "UserId": "AIDAI...",
    "Account": "016495285575",
    "Arn": "arn:aws:iam::016495285575:user/datasync-client"
}
```

#### Step 3.3: Run Installation

```bash
./install.sh
```

The installer will:
1. Create directory structure
2. Install scripts
3. Copy configuration
4. Test AWS connectivity
5. Create test file

Expected output:
```
===============================================
DataSync Simulator Installation
===============================================

Client: acme-corp
Home directory: /home/client/datasync-acme-corp

Creating directories...
✓ Directories created

Installing scripts...
✓ Scripts installed

Installing configuration...
✓ Configuration installed to: /home/client/datasync-config.env

Testing AWS connectivity...
✓ AWS credentials valid

Creating test file...
✓ Test file created: /home/client/datasync-acme-corp/source/test-installation.txt

===============================================
Installation Complete!
===============================================

Next steps:
1. Source configuration: source ~/datasync-config.env
2. Start monitor: cd /home/client/datasync-acme-corp/scripts && ./start-monitor.sh
3. Or manual sync: cd /home/client/datasync-acme-corp/scripts && ./sync-now.sh

Hot folder: /home/client/datasync-acme-corp/source
Logs: /home/client/datasync-acme-corp/logs
```

---

### Phase 4: Testing - 15 minutes

#### Step 4.1: Initial Test Sync

```bash
# Load configuration
source ~/datasync-config.env

# Go to scripts directory
cd $SCRIPTS_DIR

# Run manual sync
./sync-now.sh
```

Expected output:
```
╔════════════════════════════════════════════════════════════╗
║           Manual Sync Trigger                              ║
╚════════════════════════════════════════════════════════════╝

[INFO] DataSync Simulator Starting
[INFO] Source: /home/client/datasync-acme-corp/source
[INFO] Destination: s3://datasync-acme-corp-20251016/uploads/
[INFO] Files to sync: 1 files (89 bytes)

[INFO] Calculating SHA256 checksums for all files...
[INFO] ✓ Calculated checksums for 1 files
[INFO] Checksums saved to: .../checksums-20251016-141523.txt

[INFO] Starting sync operation...
upload: ../source/test-installation.txt to s3://datasync-acme-corp-20251016/uploads/test-installation.txt

[INFO] ✅ Sync completed successfully
[INFO] Duration: 3 seconds

✅ Sync completed successfully
```

#### Step 4.2: Verify in S3

```bash
# List files in S3
aws s3 ls s3://datasync-acme-corp-20251016/uploads/ --recursive --profile $AWS_PROFILE
```

Expected output:
```
2025-10-16 14:15:26         89 test-installation.txt
```

#### Step 4.3: Test Checksum Verification

```bash
./verify-checksums.sh
```

Expected output:
```
Using most recent checksum file: .../checksums-20251016-141523.txt

======================================
Checksum Verification
======================================

Verifying files...

  Verifying: test-installation.txt                          ✓

======================================
Verification Summary
======================================
Total files:     1
Verified:        1
Errors:          0

✅ All checksums verified successfully!
```

---

### Phase 5: Start Production - 10 minutes

#### Step 5.1: Start Hot Folder Monitor

```bash
cd $SCRIPTS_DIR
./start-monitor.sh
```

Expected output:
```
Starting hot folder monitor...

✅ Monitor started successfully (PID: 12345)

The monitor is now watching for file changes and will
automatically sync to S3 when files are added/modified.

Commands:
  • Stop monitor:    ./stop-monitor.sh
  • Check status:    ./check-status.sh
  • View logs:       tail -f ~/datasync-acme-corp/logs/monitor-20251016.log
```

#### Step 5.2: Verify Monitor is Running

```bash
./check-status.sh
```

Or check process:
```bash
ps aux | grep hotfolder-monitor
```

#### Step 5.3: Test Automatic Detection

In a new terminal:

```bash
# Add a test file
echo "Auto-detection test $(date)" > $SOURCE_DIR/auto-test.txt

# Watch the monitor log
tail -f $LOGS_DIR/monitor-$(date +%Y%m%d).log
```

Within 30 seconds, you should see:
```
[2025-10-16 14:20:15] ⚡ Changes detected!
[2025-10-16 14:20:15]   Files: 2
[2025-10-16 14:20:15]   Total size: 150
[2025-10-16 14:20:15] 📤 Triggering DataSync task...
[2025-10-16 14:20:18] ✓ Sync started
```

---

## Post-Deployment

### Configuration Review

#### Email Alerts (If Configured)

1. Client must confirm SNS subscription
2. Check email: "AWS Notification - Subscription Confirmation"
3. Click "Confirm subscription"
4. Test alert:
   ```bash
   aws sns publish \
     --topic-arn $SNS_TOPIC_ARN \
     --message "Test alert from DataSync" \
     --profile $AWS_PROFILE
   ```

#### Monitoring Setup

**View Logs:**
```bash
# Today's sync log
tail -f $LOGS_DIR/sync-$(date +%Y%m%d).log

# Today's monitor log
tail -f $LOGS_DIR/monitor-$(date +%Y%m%d).log

# Last sync metadata
cat $LOGS_DIR/last-sync.json | jq .
```

**Check S3 Usage:**
```bash
aws s3 ls s3://$BUCKET_NAME/$S3_SUBDIRECTORY/ --recursive --human-readable --summarize --profile $AWS_PROFILE
```

### Documentation Handoff

Provide client with:
1. ✅ Configuration file location: `~/datasync-config.env`
2. ✅ Operations manual: `docs/OPERATIONS_MANUAL.md`
3. ✅ Troubleshooting guide: `docs/TROUBLESHOOTING.md`
4. ✅ Migration plan: `docs/MIGRATION_PLAN.md`
5. ✅ Contact information for support

---

## Client Training

### Training Checklist (30 minutes)

#### Part 1: Adding Files (5 minutes)

```bash
# Show client the hot folder
cd $SOURCE_DIR
pwd

# Add a file
cp /path/to/their/file.pdf .

# Show auto-sync
tail -f $LOGS_DIR/monitor-$(date +%Y%m%d).log
```

#### Part 2: Manual Operations (10 minutes)

```bash
# Manual sync
cd $SCRIPTS_DIR
./sync-now.sh

# Check status
./check-status.sh

# Verify checksums
./verify-checksums.sh

# Stop monitor (if needed)
./stop-monitor.sh

# Restart monitor
./start-monitor.sh
```

#### Part 3: Viewing Results (10 minutes)

**Via AWS CLI:**
```bash
source ~/datasync-config.env
aws s3 ls s3://$BUCKET_NAME/$S3_SUBDIRECTORY/ --recursive --profile $AWS_PROFILE
```

**Via AWS Console:**
1. Log into AWS Console: https://console.aws.amazon.com/s3/
2. Navigate to bucket: `datasync-acme-corp-20251016`
3. Browse folders
4. Download files to verify

#### Part 4: Common Issues (5 minutes)

Show client how to:
1. Check if monitor is running
2. View logs
3. Test AWS credentials
4. When to call for support

---

## Troubleshooting

### Issue: Monitor Won't Start

**Symptoms:** ./start-monitor.sh fails or monitor stops immediately

**Solutions:**
```bash
# Check if already running
ps aux | grep hotfolder-monitor

# Kill existing process
pkill -f hotfolder-monitor.sh

# Check configuration
source ~/datasync-config.env
echo $SOURCE_DIR  # Should show directory path

# Check AWS credentials
aws sts get-caller-identity --profile $AWS_PROFILE

# Start with verbose logging
cd $SCRIPTS_DIR
bash -x ./start-monitor.sh
```

### Issue: Files Not Syncing

**Symptoms:** Files added to hot folder but not appearing in S3

**Solutions:**
```bash
# Check monitor is running
./check-status.sh

# Manual sync to test
./sync-now.sh

# Check AWS credentials
aws s3 ls s3://$BUCKET_NAME --profile $AWS_PROFILE

# Check permissions on hot folder
ls -la $SOURCE_DIR

# View sync logs
tail -100 $LOGS_DIR/sync-$(date +%Y%m%d).log
```

### Issue: Checksum Verification Fails

**Symptoms:** verify-checksums.sh reports mismatches

**Solutions:**
1. Check if file was modified after upload
2. Re-sync the specific file
3. Verify network stability during upload
4. Check S3 bucket versioning

### Issue: High AWS Costs

**Symptoms:** Bill higher than expected

**Solutions:**
```bash
# Check S3 usage
aws s3 ls s3://$BUCKET_NAME --recursive --summarize --human-readable --profile $AWS_PROFILE

# Review transfer logs
grep "Bytes" $LOGS_DIR/last-sync.json

# Check for duplicate uploads
# Review CloudWatch logs for errors causing retries
```

---

## Success Criteria

✅ **Installation Successful:**
- [ ] All scripts executable
- [ ] Configuration file created
- [ ] AWS credentials valid
- [ ] Directories created

✅ **Functionality Verified:**
- [ ] Manual sync works
- [ ] Files appear in S3
- [ ] Checksums verified
- [ ] Hot folder monitor running
- [ ] Auto-detection working

✅ **Client Trained:**
- [ ] Can add files to hot folder
- [ ] Can run manual sync
- [ ] Can check status
- [ ] Can view S3 files
- [ ] Knows who to contact for support

✅ **Documentation Provided:**
- [ ] Operations manual delivered
- [ ] Troubleshooting guide available
- [ ] Contact information shared
- [ ] Migration plan discussed

---

## Next Steps

### Week 1: Monitor & Support
- Daily check-ins with client
- Review logs for issues
- Address any questions
- Optimize configuration if needed

### Month 1: Performance Review
- Analyze transfer volumes
- Review costs
- Collect client feedback
- Document any improvements

### Month 3: Migration Planning
- Review transfer metrics
- Assess need for full DataSync agent
- Run migration readiness check:
  ```bash
  ./migration/prepare-migration.sh
  ```
- Schedule migration if justified

---

## Support Contacts

**For Deployment Issues:**
- Your contact: [YOUR NAME/EMAIL]
- AWS Support: [AWS SUPPORT TIER]

**For Client Questions:**
- Primary: [CLIENT CONTACT]
- Backup: [BACKUP CONTACT]

**Escalation Path:**
1. Check `docs/TROUBLESHOOTING.md`
2. Review logs
3. Contact your support team
4. AWS Support (if needed)

---

**Deployment Guide Version**: 1.0
**Last Updated**: October 2025
**Status**: Production Ready

**Congratulations on completing the deployment!** 🎉
