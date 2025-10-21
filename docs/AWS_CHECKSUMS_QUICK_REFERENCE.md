# AWS Additional Checksums - Quick Reference Guide

## TL;DR - What Changed?

**Before:** Manual SHA256 checksums, download files to verify (slow, costly)
**After:** AWS calculates checksums during upload, verifies without downloads (fast, free)

**Bottom Line:** 12x faster uploads, 99.996% lower verification costs

---

## Quick Start

### For New Users
Just use the defaults - you're already set up optimally:
```bash
export CHECKSUM_ALGORITHM="CRC64NVME"  # Fast, automatic
export VERIFY_AFTER_UPLOAD="false"     # No downloads needed
```

### For Existing Users
Update your config file to enable AWS Additional Checksums:
```bash
# Edit config file
nano ~/datasync-client-config.env

# Change or add:
export CHECKSUM_ALGORITHM="CRC64NVME"
export VERIFY_AFTER_UPLOAD="false"
```

---

## Algorithm Selection Guide

### Choose Your Algorithm in 10 Seconds

**Most Users (Recommended):**
```bash
export CHECKSUM_ALGORITHM="CRC64NVME"
```
- Fastest option (3+ GB/s)
- AWS default as of Dec 2024
- Perfect for general use

**Compliance/Regulatory:**
```bash
export CHECKSUM_ALGORITHM="SHA256"
```
- Cryptographic security
- Required for financial/healthcare/government
- Slower but meets compliance needs

**Legacy/Disable:**
```bash
export CHECKSUM_ALGORITHM="NONE"
```
- Disables AWS checksums
- Uses old manual SHA256 method
- Only for backward compatibility

---

## Performance Cheat Sheet

### Upload Times (100GB file)

| Algorithm | Time | Speed | Use When |
|-----------|------|-------|----------|
| **CRC64NVME** | 30-60s | 3+ GB/s | General use (RECOMMENDED) |
| **CRC32C** | 30-60s | 3+ GB/s | Hardware accelerated (Intel) |
| CRC32 | 60-90s | 1-2 GB/s | Older systems |
| SHA256 | 7+ min | 240 MB/s | Compliance required |
| SHA1 | 5+ min | 400 MB/s | Legacy (not recommended) |

### Verification Costs (100GB)

| Method | Cost | Time | Downloads |
|--------|------|------|-----------|
| **AWS API (NEW)** | **$0.0004** | **Seconds** | **None** |
| Download (OLD) | $9.00+ | 10-15 min | 100GB |

---

## Common Commands

### Check Current Configuration
```bash
source ~/datasync-client-config.env
echo "Algorithm: $CHECKSUM_ALGORITHM"
echo "Verification: $VERIFY_AFTER_UPLOAD"
```

### Run Sync with Checksums
```bash
./scripts/datasync-simulator.sh
```
That's it! Checksums happen automatically.

### Verify AWS CLI Version
```bash
aws --version
aws s3 sync help | grep checksum
```
Should show `--checksum-algorithm` parameter.

### Check Last Sync Results
```bash
cat ~/datasync-test/logs/last-sync.json | grep -A 6 checksum
```

---

## Configuration Examples

### Example 1: Video Production (Speed Priority)
```bash
export ENABLE_CHECKSUM_VERIFICATION="true"
export CHECKSUM_ALGORITHM="CRC64NVME"
export VERIFY_AFTER_UPLOAD="false"
```
**Result:** Fastest uploads, automatic verification, no downloads

### Example 2: Financial Services (Compliance Priority)
```bash
export ENABLE_CHECKSUM_VERIFICATION="true"
export CHECKSUM_ALGORITHM="SHA256"
export VERIFY_AFTER_UPLOAD="false"
```
**Result:** Cryptographic checksums, regulatory compliance, AWS verification

### Example 3: Mixed Environment (During Migration)
```bash
export ENABLE_CHECKSUM_VERIFICATION="true"
export CHECKSUM_ALGORITHM="CRC64NVME"
export VERIFY_AFTER_UPLOAD="true"  # For old files without checksums
```
**Result:** New files use AWS checksums, old files verified with legacy method

### Example 4: Complete Disable
```bash
export ENABLE_CHECKSUM_VERIFICATION="false"
export CHECKSUM_ALGORITHM="NONE"
export VERIFY_AFTER_UPLOAD="false"
```
**Result:** No checksums at all (not recommended)

---

## Troubleshooting

### Problem: Upload fails with "Unknown options: --checksum-algorithm"
**Fix:** Update AWS CLI
```bash
pip install --upgrade awscli
aws --version  # Should be v2.x or later
```

### Problem: Verification shows "No checksum found"
**Fix:** Normal for old files. Options:
1. Ignore warnings (old files from before checksums enabled)
2. Re-upload files to add checksums
3. Enable `VERIFY_AFTER_UPLOAD="true"` temporarily

### Problem: Uploads are slow with SHA256
**Fix:** Expected behavior
- SHA256 is CPU-intensive
- If compliance doesn't require it, switch to CRC64NVME
- If required, accept slower speed or use faster hardware

### Problem: BadDigest errors during upload
**Fix:** Indicates actual corruption
1. Check your network connection
2. Verify source file isn't corrupted
3. Retry the upload
4. Check disk health if errors persist

---

## What the Script Does

### During Upload
1. Reads file from disk
2. **Calculates checksum during upload (single-pass)**
3. Sends checksum to S3 as HTTP trailer
4. **S3 validates checksum BEFORE storing**
5. Rejects upload if checksum mismatch (BadDigest error)
6. Stores checksum with object metadata

### During Verification
1. **Queries S3 metadata (NO download)**
2. Retrieves checksum from object metadata
3. Logs checksum value
4. Reports success/missing checksums
5. Completes in seconds

---

## Key Benefits

### Speed
- **12x faster** than manual SHA256 (CRC64NVME vs SHA256)
- Single-pass operation (calculate during upload, not before)
- Hardware acceleration (CRC algorithms use CPU instructions)

### Cost
- **99.996% cheaper** verification ($0.0004 vs $9.00 per 100GB)
- No download costs for verification
- Milliseconds of API time vs minutes of transfer

### Reliability
- Server-side validation (AWS checks before storing)
- Automatic rejection of corrupted uploads
- Checksums persist throughout object lifecycle

### Simplicity
- No pre-calculation step
- No manual checksum tracking
- No download-verify-delete workflow

---

## Migration Checklist

### Before You Start
- [ ] Check AWS CLI version (`aws --version`)
- [ ] Update if needed (`pip install --upgrade awscli`)
- [ ] Backup current config file

### Update Configuration
- [ ] Set `CHECKSUM_ALGORITHM="CRC64NVME"` (or SHA256 for compliance)
- [ ] Set `VERIFY_AFTER_UPLOAD="false"`
- [ ] Keep `ENABLE_CHECKSUM_VERIFICATION="true"`

### Test
- [ ] Run sync with test files
- [ ] Check logs for "AWS Additional Checksums" messages
- [ ] Verify no errors
- [ ] Check `last-sync.json` for algorithm confirmation

### Production
- [ ] Run production sync
- [ ] Monitor first few runs
- [ ] Verify checksums showing in logs
- [ ] Celebrate faster uploads! 🎉

---

## When to Use What

### Use CRC64NVME When:
✅ You want fastest uploads
✅ Files are 100GB+ video/media
✅ Speed matters more than cryptographic security
✅ Trust your network infrastructure
✅ **This is 95% of use cases**

### Use SHA256 When:
✅ Compliance requires cryptographic hash
✅ Financial/healthcare/government data
✅ Audit trail needs crypto-strength verification
✅ Regulatory requirements specify SHA256
✅ **Only when explicitly required**

### Use CRC32C When:
✅ Have Intel CPU with SSE 4.2
✅ Want hardware acceleration
✅ CRC64NVME not supported by AWS CLI version
✅ **Good alternative to CRC64NVME**

### Use NONE When:
✅ Need to disable checksums temporarily
✅ Troubleshooting issues
✅ Testing/comparison purposes
✅ **Rarely needed**

---

## FAQ

**Q: Do I need to change anything in my scripts?**
A: No, just update the config file. The script handles everything.

**Q: Will this work with my existing files?**
A: New uploads will have checksums. Old files won't (uploaded before feature enabled).

**Q: How do I add checksums to existing files?**
A: Re-upload them with checksums enabled, or just leave them as-is.

**Q: Does this cost extra?**
A: No! It's included with S3. Actually saves money on verification.

**Q: Is CRC64NVME secure enough?**
A: For accidental corruption: absolutely. For cryptographic security: use SHA256.

**Q: Can I use multiple algorithms?**
A: Each upload uses one algorithm. You can change between uploads.

**Q: What if my AWS CLI is old?**
A: Update it: `pip install --upgrade awscli`

**Q: Will this break my existing setup?**
A: No, fully backward compatible. Default behavior unchanged unless you enable it.

---

## Still Have Questions?

1. Read the comprehensive research: `docs/Checksum research.md`
2. Check implementation details: `docs/IMPLEMENTATION_SUMMARY.md`
3. Review script comments: `scripts/datasync-simulator.sh`
4. Test with small files first
5. Monitor logs during initial runs

---

## One-Line Summary

**Use `CHECKSUM_ALGORITHM="CRC64NVME"` for 12x faster uploads with automatic AWS verification - no downloads needed.**

That's it! 🚀
