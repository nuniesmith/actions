# 📋 FKS Paper Trading Test - Log Collection Guide

## Overview

This guide explains how log collection works in the FKS paper trading test and how to troubleshoot issues when logs aren't being collected properly.

---

## 🔍 Log Collection System

### Log Files Created

When a paper trading test starts, the following log files are created in `logs/<duration>hr-test-<timestamp>/`:

| File | Description | Source |
|------|-------------|--------|
| `all-services.log` | Combined logs from all containers | `docker compose logs -f` |
| `janus.log` | Janus service logs only | `docker logs -f fks_janus` |
| `execution.log` | Execution service logs | `docker logs -f fks_execution` |
| `redis.log` | Redis logs | `docker logs -f fks_redis` |
| `postgres.log` | PostgreSQL logs | `docker logs -f fks_postgres` |
| `questdb.log` | QuestDB logs | `docker logs -f fks_questdb` |
| `log-collector.pid` | PID of combined log collector | Process ID |
| `log-collector.err` | Errors from log collector | stderr output |

### How It Works

1. **Individual Service Logs:** Each service has a dedicated `docker logs -f` process writing to its own file
2. **Combined Log:** A separate process runs `docker compose logs -f` to capture all services in one file
3. **Background Processes:** All log collectors run via `nohup` in the background

---

## ⚠️ Common Issue: Empty `all-services.log`

### Symptoms

```bash
-rw-rw-r-- 1 actions actions    0 Jan 30 03:55 all-services.log  # ← 0 bytes!
-rw-rw-r-- 1 actions actions  16K Jan 30 03:57 execution.log
-rw-rw-r-- 1 actions actions  60K Jan 30 03:57 janus.log
```

Individual logs work fine, but `all-services.log` is empty.

### Root Causes

1. **Complex Command Line:** The `docker compose` command with multiple env files may fail silently
2. **Working Directory:** The log collector script may not be in the correct directory
3. **Process Death:** The collector process may start but die immediately
4. **Permission Issues:** The log file may not be writable
5. **Container Timing:** Docker compose may not find running containers yet

---

## 🛠️ Troubleshooting Steps

### Step 1: Use the Troubleshooting Script

```bash
# Navigate to your test log directory
cd ~/fks/logs/168hr-test-20260130-035359/

# Run the troubleshooting script
./troubleshoot-logs.sh
```

This will show you:
- ✅ Whether the log collector process is running
- ✅ Current log file sizes
- ✅ Container status
- ✅ Error messages from the collector
- ✅ Test if docker compose logs works manually

### Step 2: Check Log Collector Status

```bash
# Check if process is still running
cat log-collector.pid
ps -p $(cat log-collector.pid)

# If not running, check what went wrong
cat log-collector.err
```

### Step 3: Check Error Log

```bash
# View any errors from the log collector
cat log-collector.err

# Common errors you might see:
# - "No such file or directory" → Working directory issue
# - "Cannot find compose file" → Path issue
# - "Unknown shorthand flag" → Syntax error in command
```

### Step 4: Test Manual Collection

```bash
cd ~/fks

# Test if docker compose logs works at all
docker compose -f infrastructure/compose/docker-compose.yml \
  -f infrastructure/compose/docker-compose.prod.yml \
  logs --tail 20

# If this works, the issue is with the background process
# If this fails, check your docker-compose.yml files
```

---

## 🔧 Manual Fix: Restart Log Collection

If the log collector died or never started properly, restart it manually:

### Method 1: Use the Collect Script (Recommended)

```bash
# Navigate to log directory
cd ~/fks/logs/168hr-test-20260130-035359/

# Kill old collector (if running)
kill $(cat log-collector.pid) 2>/dev/null

# Clear the empty log file
> all-services.log

# Restart the collector
bash collect-logs.sh > log-collector.err 2>&1 &

# Save new PID
echo $! > log-collector.pid

# Wait a few seconds
sleep 3

# Verify it's working
tail -20 all-services.log
```

### Method 2: Direct Command

```bash
cd ~/fks

# Kill old collector
kill $(cat logs/168hr-test-*/log-collector.pid) 2>/dev/null

# Find your test log directory
TEST_LOG_DIR=$(ls -dt logs/*hr-test-* | head -1)

# Start new collector
nohup docker compose \
  -f infrastructure/compose/docker-compose.yml \
  -f infrastructure/compose/docker-compose.prod.yml \
  logs -f --timestamps >> "$TEST_LOG_DIR/all-services.log" 2>&1 &

# Save PID
echo $! > "$TEST_LOG_DIR/log-collector.pid"

# Verify
sleep 3
tail -20 "$TEST_LOG_DIR/all-services.log"
```

---

## 🔍 Debugging Commands

### Check All Log Collector Processes

```bash
# Find all docker logs processes
ps aux | grep "docker logs" | grep -v grep

# Find docker compose logs process
ps aux | grep "docker compose logs" | grep -v grep

# Count running log collectors
ps aux | grep "docker.*logs" | grep -v grep | wc -l
```

### Check Log File Growth

```bash
# Watch log file size in real-time
watch -n 2 'ls -lh logs/*/all-services.log'

# Count lines being written
watch -n 2 'wc -l logs/*/*.log'

# Tail all logs simultaneously (split screen)
tail -f logs/*/*.log
```

### Check Container Output

```bash
# Are containers actually producing logs?
docker compose logs --tail 50

# Check specific service
docker logs fks_janus --tail 50

# Check all fks containers
for container in $(docker ps --filter "name=fks" --format '{{.Names}}'); do
  echo "=== $container ==="
  docker logs $container --tail 10
done
```

---

## 🚨 Emergency: Logs Not Collecting At All

If none of the logs are collecting (all empty), try this:

```bash
cd ~/fks

# 1. Check if containers are even running
docker ps --filter "name=fks"

# 2. If no containers, something went wrong with deployment
docker compose ps

# 3. Check recent Docker events
docker events --since 5m --until 0s --filter "name=fks"

# 4. Manually view logs to see what's happening
docker compose logs --tail 100

# 5. Restart the entire test if necessary
docker compose down
docker compose up -d
```

---

## ✅ Verification Checklist

After fixing log collection, verify everything is working:

- [ ] Log collector process is running: `ps -p $(cat log-collector.pid)`
- [ ] `all-services.log` is growing: `watch ls -lh all-services.log`
- [ ] Individual service logs are growing: `ls -lh *.log`
- [ ] No errors in `log-collector.err`: `cat log-collector.err`
- [ ] Can tail logs successfully: `tail -f all-services.log`
- [ ] Logs contain recent timestamps (not stale)

---

## 💡 Prevention: Avoid This Issue

### In Future Deployments

The CI/CD workflow has been updated with these improvements:

1. **Separate Log Collection Script:** The complex `docker compose` command is now in a separate script file
2. **Error Logging:** stderr is captured to `log-collector.err` for debugging
3. **Process Verification:** After starting, the workflow checks if the collector is still running
4. **File Size Check:** The workflow verifies that `all-services.log` is receiving data
5. **Troubleshooting Script:** A helper script is automatically created for debugging

### Best Practices

1. **Always check log collector after deployment:**
   ```bash
   cd ~/fks/logs/<latest>
   ./troubleshoot-logs.sh
   ```

2. **Monitor log file sizes periodically:**
   ```bash
   watch -n 60 'ls -lh ~/fks/logs/*/*.log'
   ```

3. **Keep individual service logs as backup:**
   - Even if `all-services.log` fails, individual logs still work
   - You can manually combine them later if needed

---

## 📊 Log Analysis Tips

### Combine Individual Logs Manually

If `all-services.log` is empty but individual logs are fine:

```bash
# Merge all individual logs by timestamp
cd logs/168hr-test-20260130-035359/

# Simple concatenation (not sorted by time)
cat janus.log execution.log redis.log postgres.log questdb.log > combined-manual.log

# Sort by timestamp (if logs have timestamps)
cat *.log | grep -E '^\[?[0-9]{4}' | sort > combined-sorted.log
```

### Search Across All Logs

```bash
# Search for errors in all logs
grep -i error *.log

# Search for specific service events
grep "optimizer" *.log

# Find when a specific asset was traded
grep "BTC/USD" *.log

# Count log entries per service
wc -l *.log
```

### Monitor Log Growth Rate

```bash
# Watch log growth over time (bytes per second)
while true; do
  ls -l all-services.log | awk '{print $5}'
  sleep 5
done

# Better: Use watch with human-readable sizes
watch -n 5 'ls -lh *.log | awk "{print \$9, \$5}"'
```

---

## 🆘 Still Having Issues?

### Check These Common Problems

1. **Disk Space:**
   ```bash
   df -h /
   # If disk is full, logs can't be written
   ```

2. **File Permissions:**
   ```bash
   ls -la *.log
   # All log files should be writable by 'actions' user
   ```

3. **Docker Daemon:**
   ```bash
   sudo systemctl status docker
   # Ensure Docker is running properly
   ```

4. **Compose File Syntax:**
   ```bash
   docker compose config
   # Check for syntax errors in compose files
   ```

### Get Help

If you're still stuck:

1. Run `./troubleshoot-logs.sh` and save output
2. Check `log-collector.err` for error messages
3. Run `docker compose logs --tail 100` to see if containers are producing output
4. Check GitHub Actions workflow logs for deployment errors

---

## 📋 Quick Reference

### Essential Commands

```bash
# Check log collector status
ps -p $(cat logs/*/log-collector.pid)

# View collector errors
cat logs/*/log-collector.err

# Restart log collection
cd logs/<test-dir> && bash collect-logs.sh &

# Troubleshoot
cd logs/<test-dir> && ./troubleshoot-logs.sh

# Manual log collection
cd ~/fks && docker compose logs -f > combined.log
```

### File Locations

```
~/fks/
├── logs/
│   └── 168hr-test-20260130-035359/
│       ├── all-services.log        ← Combined (should not be 0 bytes!)
│       ├── janus.log               ← Individual service logs
│       ├── execution.log
│       ├── redis.log
│       ├── postgres.log
│       ├── questdb.log
│       ├── collect-logs.sh         ← Script to restart log collection
│       ├── troubleshoot-logs.sh    ← Diagnostic script
│       ├── check-status.sh         ← Service status script
│       ├── log-collector.pid       ← Process ID
│       └── log-collector.err       ← Error output
```

---

## ✅ Success Criteria

Your log collection is working properly when:

- ✅ `all-services.log` is **NOT** 0 bytes (should be growing)
- ✅ Log collector process is running: `ps -p $(cat log-collector.pid)` shows process
- ✅ No errors in `log-collector.err` (file may be empty or contain benign warnings)
- ✅ Individual service logs are also growing
- ✅ `tail -f all-services.log` shows live output
- ✅ Logs contain recent timestamps (within last minute)

---

## 🎯 Summary

**The most common issue:** The `docker compose logs` command is complex and may fail silently when run in the background.

**Quick fix:** Use the `troubleshoot-logs.sh` script to diagnose, then restart log collection with `collect-logs.sh`.

**Prevention:** The updated CI/CD workflow now includes better error handling and verification.

**Remember:** Individual service logs work independently, so you always have backup logs even if the combined log fails!