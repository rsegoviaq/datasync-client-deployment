# DataSync Client Deployment Kit

A comprehensive package for deploying AWS DataSync solutions with a hybrid approach: start with a cost-effective simulator and migrate to the full DataSync agent when ready.

## 📋 Overview

This deployment kit provides everything needed to implement automated file synchronization from on-premise hot folders to AWS S3 with two deployment modes:

### **Mode 1: Simulator** (Start Here)
- AWS CLI-based file synchronization
- Low cost (~$2-5/month)
- No infrastructure requirements
- Quick deployment (1-2 hours)
- Perfect for testing, development, and low-volume transfers

### **Mode 2: Full DataSync Agent** (Migrate When Ready)
- Enterprise-grade AWS DataSync agent
- High performance (up to 10 Gbps)
- Production reliability
- Higher cost (~$220-265/month)
- Ideal for high-volume production workloads

## 🚀 Quick Start

### Step 1: Setup for New Client

Run the interactive setup wizard:

```bash
./setup-client.sh client-name
```

This will:
- ✅ Collect client information
- ✅ Configure AWS credentials
- ✅ Create S3 bucket and IAM roles
- ✅ Generate client-specific configuration
- ✅ Create deployment package

### Step 2: Deploy to Client Site

Transfer the generated package to the client:

```bash
# Package location
packages/client-name-deployment.tar.gz
```

On the client machine:

```bash
tar -xzf client-name-deployment.tar.gz
cd client-name-deployment
./install.sh
```

### Step 3: Start Monitoring

```bash
source ~/datasync-config.env
cd $SCRIPTS_DIR
./start-monitor.sh
```

## 📁 Package Structure

```
datasync-client-deployment/
├── README.md                     # This file
├── setup-client.sh               # Interactive setup wizard
│
├── scripts/                      # Operational scripts
│   ├── datasync-simulator.sh    # Core sync engine (with checksums!)
│   ├── hotfolder-monitor.sh     # Auto-detect file changes
│   ├── start-monitor.sh         # Start monitoring
│   ├── stop-monitor.sh          # Stop monitoring
│   ├── sync-now.sh              # Manual sync trigger
│   ├── check-status.sh          # Check sync status
│   └── verify-checksums.sh      # Verify file integrity
│
├── config/                       # Configuration templates
│   └── config-template.env      # Environment variables template
│
├── docs/                         # Documentation
│   ├── DEPLOYMENT_GUIDE.md      # Detailed deployment instructions
│   ├── OPERATIONS_MANUAL.md     # Daily operations guide
│   ├── MIGRATION_PLAN.md        # Migration to DataSync agent
│   ├── SIMULATOR_VS_AGENT.md    # Comparison & decision guide
│   └── TROUBLESHOOTING.md       # Common issues & solutions
│
├── migration/                    # Migration tools
│   ├── prepare-migration.sh     # Readiness assessment
│   └── cutover-to-datasync.sh   # Migrate to full agent
│
└── packages/                     # Generated client packages
    └── [client]-deployment/      # Ready-to-deploy package
```

## ✨ Features

### Simulator Mode Features

✅ **Checksum Verification (NEW!)**
- SHA256 hashing before upload
- Optional post-upload verification
- Audit trail for compliance
- Stored with timestamps

✅ **Automated Monitoring**
- Hot folder auto-detection
- Configurable check intervals (default: 30 seconds)
- File change detection
- Automatic sync trigger

✅ **Cost Optimization**
- S3 Intelligent-Tiering storage
- Minimal AWS service charges
- Estimated $2-5/month

✅ **Reliability**
- Detailed logging
- Error handling
- Manual trigger option
- Status checking

### Migration Path Features

✅ **Smooth Transition**
- Parallel testing capability
- Gradual cutover process
- Rollback capability
- No data loss

✅ **Enterprise Features (Agent Mode)**
- 99.9%+ reliability
- Bandwidth throttling
- Built-in retry logic
- CloudWatch integration
- Scheduled transfers

## 🎯 When to Use Which Mode

### Use Simulator Mode When:
- ✅ Monthly transfer volume < 500GB
- ✅ Budget constrained (~$2-5/month acceptable)
- ✅ Testing or development environment
- ✅ Simple use case
- ✅ Quick deployment needed
- ✅ Current performance acceptable

### Migrate to Agent Mode When:
- ✅ Monthly transfer volume > 500GB
- ✅ Need consistent >5MB/s throughput
- ✅ Require bandwidth controls
- ✅ Enterprise reliability required (99.9%+)
- ✅ Compliance/audit requirements
- ✅ Budget allows ~$220/month
- ✅ Multiple sources/destinations

## 📊 Cost Comparison

| Component | Simulator | Full Agent | Difference |
|-----------|-----------|------------|------------|
| **S3 Storage** | $0.023/GB-mo | $0.023/GB-mo | Same |
| **S3 Requests** | Minimal | Minimal | Similar |
| **DataSync Service** | $0 | $2.50-5/mo | +$2.50-5 |
| **Infrastructure** | $0 | $200-245/mo | +$200-245 |
| **CloudWatch** | Minimal | $2.50/mo | +$2.50 |
| **TOTAL/month** | **$2-5** | **$220-265** | **+$215-260** |

## 📖 Documentation

### For Initial Deployment:
1. `docs/DEPLOYMENT_GUIDE.md` - Complete deployment instructions
2. `docs/OPERATIONS_MANUAL.md` - Daily operations for client staff

### For Migration:
3. `docs/MIGRATION_PLAN.md` - Step-by-step migration guide
4. `docs/SIMULATOR_VS_AGENT.md` - Detailed comparison & decision matrix

### For Support:
5. `docs/TROUBLESHOOTING.md` - Common issues and solutions
6. `docs/CHECKSUM_GUIDE.md` - Checksum verification documentation

## 🛠️ Common Operations

### Client Setup (Your Side)

```bash
# Setup new client
./setup-client.sh acme-corp

# Package will be created at:
# packages/acme-corp-deployment.tar.gz
```

### Client Installation (Client Side)

```bash
# Extract package
tar -xzf acme-corp-deployment.tar.gz
cd acme-corp-deployment

# Install
./install.sh

# Start monitoring
source ~/datasync-config.env
cd $SCRIPTS_DIR
./start-monitor.sh
```

### Daily Operations (Client Side)

```bash
# Add files to hot folder
cp files/* $SOURCE_DIR/

# Files auto-sync within 30 seconds

# Manual sync (if needed)
./sync-now.sh

# Check status
./check-status.sh

# Verify checksums
./verify-checksums.sh

# Stop monitoring
./stop-monitor.sh
```

### Migration to DataSync Agent

```bash
# Check readiness
./migration/prepare-migration.sh

# If ready, proceed with cutover
./migration/cutover-to-datasync.sh
```

## 🔧 Configuration

Each client gets a customized configuration file:

```bash
# Location: ~/datasync-config.env

# Key settings:
AWS_PROFILE="datasync-client"
BUCKET_NAME="datasync-client-20251016"
SOURCE_DIR="~/datasync-client/source"

# Checksum settings:
ENABLE_CHECKSUM_VERIFICATION="true"
VERIFY_AFTER_UPLOAD="false"

# Monitoring:
MONITOR_CHECK_INTERVAL="30"
ALERT_EMAIL="client@example.com"
```

## 📞 Support

### Setup Issues
- Review `docs/TROUBLESHOOTING.md`
- Check AWS credentials: `aws sts get-caller-identity`
- Verify S3 bucket access: `aws s3 ls s3://bucket-name`

### Operational Issues
- Check logs: `tail -f ~/datasync-client/logs/sync-$(date +%Y%m%d).log`
- Verify monitor running: `ps aux | grep hotfolder-monitor`
- Test AWS connectivity: `aws s3 ls --profile datasync-client`

### Migration Questions
- Run readiness check: `./migration/prepare-migration.sh`
- Review cost analysis in output
- Consult `docs/MIGRATION_PLAN.md`

## 🎓 Training Materials

Included documentation provides:
- ✅ Step-by-step deployment guide
- ✅ Operations manual for client staff
- ✅ Troubleshooting procedures
- ✅ Migration roadmap
- ✅ Cost optimization tips

## 🔐 Security

### Simulator Mode:
- ✅ TLS encryption in transit (AWS default)
- ✅ SSE-S3 encryption at rest
- ✅ IAM role-based access control
- ✅ Public access blocked on S3
- ✅ SHA256 checksums for integrity

### Agent Mode (Additional):
- ✅ Network isolation options
- ✅ VPC endpoints support
- ✅ Enhanced audit logging
- ✅ Direct Connect support

## 📈 Success Metrics

Track these KPIs:

| Metric | Simulator Target | Agent Target |
|--------|------------------|--------------|
| Transfer Success Rate | >95% | >99% |
| Average Throughput | 1-5 MB/s | 5-100 MB/s |
| Detection to Sync | <2 min | <5 min |
| Monthly Cost/GB | <$0.05 | <$0.02 |

## 🗺️ Roadmap

### Phase 1: Immediate (Week 1)
- ✅ Deploy simulator
- ✅ Train client staff
- ✅ Validate functionality

### Phase 2: Optimization (Weeks 2-4)
- Monitor performance
- Collect metrics
- Optimize configuration

### Phase 3: Migration Decision (Month 2-3)
- Analyze transfer volumes
- Review costs
- Assess need for enterprise features

### Phase 4: Migration (Month 3-6, if needed)
- Deploy DataSync agent
- Parallel testing
- Gradual cutover

## 📝 License & Attribution

Built with:
- AWS CLI
- AWS DataSync
- Bash scripting
- Comprehensive documentation

---

**Version**: 1.0
**Last Updated**: October 2025
**Status**: Production Ready

## 🎉 Getting Started Checklist

- [ ] Run `./setup-client.sh [client-name]`
- [ ] Review generated configuration
- [ ] Transfer package to client
- [ ] Install on client machine
- [ ] Test with sample files
- [ ] Train client staff
- [ ] Monitor for 1 week
- [ ] Schedule migration review meeting

For detailed instructions, see `docs/DEPLOYMENT_GUIDE.md`

---

**Questions?** Check `docs/TROUBLESHOOTING.md` or review the comprehensive documentation in the `docs/` directory.
