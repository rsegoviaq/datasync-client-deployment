# AWS Additional Checksums - Usage Examples

## Real-World Usage Scenarios

### Scenario 1: Video Production Company (Recommended Setup)

**Background:** Uploading 100GB+ video files daily, prioritizing speed.

**Configuration:**
```bash
# config/config-template.env
export ENABLE_CHECKSUM_VERIFICATION="true"
export CHECKSUM_ALGORITHM="CRC64NVME"
export VERIFY_AFTER_UPLOAD="false"
```

**Expected Results:**
- Upload time: 10-15 minutes on 10Gbps connection
- Checksum overhead: ~30-60 seconds (negligible)
- Verification: Instant (API call, no downloads)
- Cost: $0.0004 per 1000 files

**Log Output:**
```
[INFO] [2025-10-21 10:00:00] ======================================
[INFO] [2025-10-21 10:00:00] DataSync Simulator Starting
[INFO] [2025-10-21 10:00:00] ======================================
[INFO] [2025-10-21 10:00:00] Source: /home/user/videos
[INFO] [2025-10-21 10:00:00] Destination: s3://my-bucket/videos/
[INFO] [2025-10-21 10:00:00] AWS Profile: production
[INFO] [2025-10-21 10:00:00] Region: us-west-2
[INFO] [2025-10-21 10:00:00]
[INFO] [2025-10-21 10:00:00] AWS Additional Checksums Configuration:
[INFO] [2025-10-21 10:00:00]   Checksum Verification: true
[INFO] [2025-10-21 10:00:00]   Checksum Algorithm: CRC64NVME
[INFO] [2025-10-21 10:00:00]   Server-side verification: ENABLED (AWS validates automatically)
[INFO] [2025-10-21 10:00:00]   Performance benefit: Single-pass upload with trailing checksums
[INFO] [2025-10-21 10:00:00]   Legacy download verification: false
[INFO] [2025-10-21 10:00:00]
[INFO] [2025-10-21 10:00:00] Files to sync: 5 files (512GB)
[INFO] [2025-10-21 10:00:00]
[INFO] [2025-10-21 10:00:00] AWS Additional Checksums enabled - checksums will be calculated during upload
[INFO] [2025-10-21 10:00:00] Algorithm: CRC64NVME (hardware-accelerated, single-pass operation)
[INFO] [2025-10-21 10:00:00]
[INFO] [2025-10-21 10:00:00] Starting sync operation...
[INFO] [2025-10-21 10:00:00] Using AWS Additional Checksums with algorithm: CRC64NVME
[INFO] [2025-10-21 10:00:00] S3 will validate checksums automatically during upload (HTTP trailers)
[INFO] [2025-10-21 10:00:00] Executing: aws s3 sync with checksum verification...
upload: ./video1.mp4 to s3://my-bucket/videos/video1.mp4
upload: ./video2.mp4 to s3://my-bucket/videos/video2.mp4
...
[INFO] [2025-10-21 10:45:30]
[INFO] [2025-10-21 10:45:30] ======================================
[INFO] [2025-10-21 10:45:30] ✅ Sync completed successfully
[INFO] [2025-10-21 10:45:30] Duration: 2730 seconds
[INFO] [2025-10-21 10:45:30] ======================================
[INFO] [2025-10-21 10:45:30]
[INFO] [2025-10-21 10:45:30] Verifying uploads using AWS Additional Checksums API...
[INFO] [2025-10-21 10:45:30] Note: This checks S3 metadata without downloading files (fast and free)
[INFO] [2025-10-21 10:45:35] AWS checksum verification complete: 5 verified, 0 missing/errors
[INFO] [2025-10-21 10:45:35] ✅ All AWS checksums verified successfully
```

---

### Scenario 2: Financial Services (Compliance Requirements)

**Background:** Regulatory compliance requires cryptographic checksums.

**Configuration:**
```bash
# config/config-template.env
export ENABLE_CHECKSUM_VERIFICATION="true"
export CHECKSUM_ALGORITHM="SHA256"
export VERIFY_AFTER_UPLOAD="false"
```

**Expected Results:**
- Upload time: Slightly longer (SHA256 is slower)
- Checksum overhead: ~7 minutes for 100GB
- Verification: Instant (API call)
- Compliance: Meets cryptographic hash requirements

**Log Output:**
```
[INFO] [2025-10-21 11:00:00] AWS Additional Checksums Configuration:
[INFO] [2025-10-21 11:00:00]   Checksum Verification: true
[INFO] [2025-10-21 11:00:00]   Checksum Algorithm: SHA256
[INFO] [2025-10-21 11:00:00]   Server-side verification: ENABLED (AWS validates automatically)
[INFO] [2025-10-21 11:00:00]   Performance benefit: Single-pass upload with trailing checksums
[INFO] [2025-10-21 11:00:00]
[INFO] [2025-10-21 11:00:00] Using AWS Additional Checksums with algorithm: SHA256
[INFO] [2025-10-21 11:00:00] S3 will validate checksums automatically during upload (HTTP trailers)
```

---

### Scenario 3: Migration from Legacy System

**Background:** Existing deployment with old SHA256 checksums, gradually migrating.

**Configuration:**
```bash
# config/config-template.env
export ENABLE_CHECKSUM_VERIFICATION="true"
export CHECKSUM_ALGORITHM="CRC64NVME"
export VERIFY_AFTER_UPLOAD="true"  # Keep for old files without AWS checksums
```

**Expected Results:**
- New uploads: Fast with CRC64NVME
- Old files: Verified with legacy download method
- Can disable VERIFY_AFTER_UPLOAD after all files re-uploaded

**Log Output:**
```
[INFO] [2025-10-21 12:00:00] Verifying uploads using AWS Additional Checksums API...
[INFO] [2025-10-21 12:00:00] Note: This checks S3 metadata without downloading files (fast and free)
[INFO] [2025-10-21 12:00:05] AWS checksum verification complete: 3 verified, 2 missing/errors
[WARN] [2025-10-21 12:00:05] ⚠ Some files missing AWS checksums (may have been uploaded before checksums enabled)
[INFO] [2025-10-21 12:00:05]
[WARN] [2025-10-21 12:00:05] Legacy download-based verification enabled (SLOW and COSTLY)
[WARN] [2025-10-21 12:00:05] Using LEGACY checksum verification (downloads files from S3)
[WARN] [2025-10-21 12:00:05] This is NOT RECOMMENDED - use AWS Additional Checksums instead
```

---

### Scenario 4: Disabled Checksums (Testing/Troubleshooting)

**Background:** Temporarily disable checksums for troubleshooting.

**Configuration:**
```bash
# config/config-template.env
export ENABLE_CHECKSUM_VERIFICATION="false"
export CHECKSUM_ALGORITHM="NONE"
export VERIFY_AFTER_UPLOAD="false"
```

**Expected Results:**
- No checksum calculation
- No verification
- Fastest possible upload (no overhead)
- Use only for testing

**Log Output:**
```
[INFO] [2025-10-21 13:00:00] AWS Additional Checksums Configuration:
[INFO] [2025-10-21 13:00:00]   Checksum Verification: false
[INFO] [2025-10-21 13:00:00]   Checksum Algorithm: NONE
[INFO] [2025-10-21 13:00:00]   Legacy download verification: false
[INFO] [2025-10-21 13:00:00]
[INFO] [2025-10-21 13:00:00] AWS Additional Checksums disabled - using standard sync
```

---

### Scenario 5: Hardware-Accelerated CRC32C (Intel Systems)

**Background:** Intel CPU with SSE 4.2, want maximum performance.

**Configuration:**
```bash
# config/config-template.env
export ENABLE_CHECKSUM_VERIFICATION="true"
export CHECKSUM_ALGORITHM="CRC32C"
export VERIFY_AFTER_UPLOAD="false"
```

**Expected Results:**
- Hardware-accelerated checksums (Intel SSE 4.2)
- ~3+ GB/s throughput
- Minimal CPU overhead
- Same performance as CRC64NVME

**Log Output:**
```
[INFO] [2025-10-21 14:00:00]   Checksum Algorithm: CRC32C
[INFO] [2025-10-21 14:00:00] AWS Additional Checksums enabled - checksums will be calculated during upload
[INFO] [2025-10-21 14:00:00] Algorithm: CRC32C (hardware-accelerated, single-pass operation)
```

---

## Common Workflows

### Workflow 1: First-Time Setup

```bash
# 1. Check AWS CLI version
aws --version
# Expected: AWS CLI version 2.x or later

# 2. Test checksum support
aws s3 sync help | grep -i checksum
# Expected: Should show --checksum-algorithm parameter

# 3. Configure DataSync
cd ~/datasync-client-deployment
nano config/config-template.env

# Add/modify:
export CHECKSUM_ALGORITHM="CRC64NVME"
export VERIFY_AFTER_UPLOAD="false"

# 4. Test with small files
mkdir -p ~/test-upload
echo "test data" > ~/test-upload/test.txt

# Update config to point to test directory
export SOURCE_DIR="~/test-upload"

# 5. Run sync
./scripts/datasync-simulator.sh

# 6. Verify logs show AWS checksums
tail -f ~/datasync-test/logs/sync-*.log

# 7. Check metadata
cat ~/datasync-test/logs/last-sync.json | jq '.checksum_verification'
```

---

### Workflow 2: Verifying Checksums Post-Upload

```bash
# Quick verification using script
./scripts/datasync-simulator.sh
# Verification happens automatically after sync

# Manual verification of specific file
aws s3api head-object \
  --bucket my-bucket \
  --key path/to/file.mp4 \
  --checksum-mode ENABLED \
  --profile production \
  --region us-west-2 \
  --query 'ChecksumCRC64NVME'

# Expected output:
# "AAAAAA=="  (base64-encoded checksum)
```

---

### Workflow 3: Migrating Existing Files

```bash
# Step 1: Enable AWS checksums
export CHECKSUM_ALGORITHM="CRC64NVME"

# Step 2: Keep legacy verification for now
export VERIFY_AFTER_UPLOAD="true"

# Step 3: Run sync (new files get AWS checksums, old files verified with legacy)
./scripts/datasync-simulator.sh

# Step 4: Check which files have AWS checksums
aws s3api list-objects-v2 \
  --bucket my-bucket \
  --prefix videos/ \
  --profile production \
  --region us-west-2 | \
  jq '.Contents[] | {Key: .Key, Size: .Size}'

# For each file, check if it has checksums
for key in $(aws s3api list-objects-v2 --bucket my-bucket --prefix videos/ --query 'Contents[].Key' --output text); do
  echo "Checking: $key"
  aws s3api head-object \
    --bucket my-bucket \
    --key "$key" \
    --checksum-mode ENABLED \
    --profile production \
    --region us-west-2 \
    --query 'ChecksumCRC64NVME' 2>/dev/null || echo "  No checksum"
done

# Step 5: Re-upload files without checksums
# Option A: Delete and re-upload
# Option B: Copy in place to add checksums
aws s3 cp \
  s3://my-bucket/path/to/file.mp4 \
  s3://my-bucket/path/to/file.mp4 \
  --checksum-algorithm CRC64NVME \
  --profile production \
  --region us-west-2

# Step 6: Once all files have checksums, disable legacy verification
export VERIFY_AFTER_UPLOAD="false"
```

---

### Workflow 4: Troubleshooting BadDigest Errors

```bash
# Scenario: Upload fails with BadDigest error

# 1. Check logs for error details
grep -i "baddigest" ~/datasync-test/logs/sync-*.log

# Expected output:
# [ERROR] [2025-10-21 15:30:45] AWS checksum validation failed (BadDigest error detected)
# [ERROR] [2025-10-21 15:30:45] This indicates data corruption during transmission or calculation error

# 2. Verify source file integrity
sha256sum /path/to/source/file.mp4

# 3. Check disk health
smartctl -a /dev/sda

# 4. Test network stability
ping -c 100 s3.us-west-2.amazonaws.com

# 5. Retry upload with different algorithm
export CHECKSUM_ALGORITHM="SHA256"  # Try cryptographic hash
./scripts/datasync-simulator.sh

# 6. If error persists, investigate source data
md5sum /path/to/source/file.mp4
# Wait 1 minute
md5sum /path/to/source/file.mp4
# Compare - if different, disk corruption

# 7. If source is good, test with smaller chunk
# Create test file
dd if=/path/to/source/file.mp4 of=/tmp/test-chunk.mp4 bs=1M count=100

# Upload test chunk
aws s3 cp /tmp/test-chunk.mp4 \
  s3://my-bucket/test/ \
  --checksum-algorithm CRC64NVME \
  --profile production \
  --region us-west-2
```

---

### Workflow 5: Performance Comparison

```bash
# Test different algorithms with same file

# Prepare test file (100MB)
dd if=/dev/urandom of=/tmp/test-100mb.bin bs=1M count=100

# Test 1: No checksums
export CHECKSUM_ALGORITHM="NONE"
time ./scripts/datasync-simulator.sh
# Note: Duration

# Test 2: CRC64NVME
export CHECKSUM_ALGORITHM="CRC64NVME"
time ./scripts/datasync-simulator.sh
# Note: Duration

# Test 3: SHA256
export CHECKSUM_ALGORITHM="SHA256"
time ./scripts/datasync-simulator.sh
# Note: Duration

# Compare results in logs
grep "Duration:" ~/datasync-test/logs/last-sync.json

# Expected results for 100MB file:
# NONE:       ~10 seconds (baseline, network speed)
# CRC64NVME:  ~11 seconds (+1 second overhead)
# SHA256:     ~45 seconds (+35 seconds overhead)
```

---

## Advanced Examples

### Example 1: Batch Processing with Multiple Algorithms

```bash
#!/bin/bash
# Process files with dual checksums for compliance

SOURCE_DIR="/data/videos"
COMPLIANCE_LOG="/logs/compliance-checksums.csv"

# Write header
echo "Filename,SHA256,CRC64NVME,Upload_Time" > "$COMPLIANCE_LOG"

for file in "$SOURCE_DIR"/*.mp4; do
  filename=$(basename "$file")

  # Calculate local SHA256 for compliance
  sha256=$(sha256sum "$file" | cut -d' ' -f1)

  # Upload with CRC64NVME (fast)
  export CHECKSUM_ALGORITHM="CRC64NVME"
  start_time=$(date +%s)
  ./scripts/datasync-simulator.sh
  end_time=$(date +%s)
  duration=$((end_time - start_time))

  # Get CRC64NVME from S3
  crc64=$(aws s3api head-object \
    --bucket my-bucket \
    --key "videos/$filename" \
    --checksum-mode ENABLED \
    --profile production \
    --region us-west-2 \
    --query 'ChecksumCRC64NVME' \
    --output text)

  # Log both checksums
  echo "$filename,$sha256,$crc64,$duration" >> "$COMPLIANCE_LOG"

  echo "Processed: $filename (SHA256: $sha256, CRC64: $crc64, Time: ${duration}s)"
done

echo "Compliance log saved to: $COMPLIANCE_LOG"
```

---

### Example 2: Automated Health Check

```bash
#!/bin/bash
# Daily health check - verify all S3 objects have checksums

BUCKET="my-bucket"
PREFIX="videos/"
REPORT="/logs/checksum-health-$(date +%Y%m%d).txt"

echo "Checksum Health Check - $(date)" > "$REPORT"
echo "========================================" >> "$REPORT"
echo "" >> "$REPORT"

total=0
with_checksums=0
without_checksums=0

# Get all objects
for key in $(aws s3api list-objects-v2 \
  --bucket "$BUCKET" \
  --prefix "$PREFIX" \
  --query 'Contents[].Key' \
  --output text \
  --profile production \
  --region us-west-2); do

  ((total++))

  # Check for checksum
  checksum=$(aws s3api head-object \
    --bucket "$BUCKET" \
    --key "$key" \
    --checksum-mode ENABLED \
    --profile production \
    --region us-west-2 \
    --query 'ChecksumCRC64NVME' \
    --output text 2>/dev/null)

  if [ "$checksum" != "None" ] && [ -n "$checksum" ]; then
    ((with_checksums++))
    echo "✓ $key: $checksum" >> "$REPORT"
  else
    ((without_checksums++))
    echo "✗ $key: NO CHECKSUM" >> "$REPORT"
  fi
done

echo "" >> "$REPORT"
echo "Summary:" >> "$REPORT"
echo "  Total files: $total" >> "$REPORT"
echo "  With checksums: $with_checksums" >> "$REPORT"
echo "  Without checksums: $without_checksums" >> "$REPORT"
echo "  Coverage: $(awk "BEGIN {print ($with_checksums/$total)*100}")%" >> "$REPORT"

cat "$REPORT"
```

---

## Summary

All examples demonstrate:
- **Performance:** Fast uploads with minimal overhead
- **Cost:** Near-zero verification costs
- **Reliability:** Automatic server-side validation
- **Flexibility:** Multiple algorithms for different needs
- **Simplicity:** Easy configuration and operation

Choose the scenario that matches your use case and follow the recommended configuration.
