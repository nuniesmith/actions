#!/bin/bash
# ============================================================================
# Emergency Fix Script for Empty all-services.log
# ============================================================================
# This script fixes the issue where all-services.log is empty (0 bytes)
# while individual service logs are working fine.
#
# Usage: bash fix-empty-log.sh
# ============================================================================

set -e

echo "════════════════════════════════════════════════════════════"
echo "🔧 FIXING EMPTY all-services.log"
echo "════════════════════════════════════════════════════════════"
echo ""

# Navigate to fks directory
cd ~/fks || { echo "❌ Cannot find ~/fks directory"; exit 1; }

# Find the most recent test log directory
echo "🔍 Finding most recent test directory..."
TEST_LOG_DIR=$(ls -dt logs/*hr-test-* 2>/dev/null | head -1)

if [ -z "$TEST_LOG_DIR" ]; then
    echo "❌ No test log directories found in logs/"
    exit 1
fi

echo "✓ Found: $TEST_LOG_DIR"
echo ""

# Check current status
echo "📊 Current Status:"
ls -lh "$TEST_LOG_DIR"/*.log 2>/dev/null || echo "  No log files found"
echo ""

# Kill existing log collector if running
if [ -f "$TEST_LOG_DIR/log-collector.pid" ]; then
    OLD_PID=$(cat "$TEST_LOG_DIR/log-collector.pid")
    if ps -p $OLD_PID > /dev/null 2>&1; then
        echo "🛑 Stopping old log collector (PID: $OLD_PID)..."
        kill $OLD_PID 2>/dev/null || true
        sleep 2
    else
        echo "⚠️  Old log collector not running (PID: $OLD_PID)"
    fi
fi

# Clear the empty log file
echo "🧹 Clearing empty all-services.log..."
> "$TEST_LOG_DIR/all-services.log"

# Find which env file to use
TEST_ENV_FILE=""
for hours in 168 72 48 24 12 6 3 1; do
    if [ -f ".env.${hours}hr-test" ]; then
        TEST_ENV_FILE=".env.${hours}hr-test"
        echo "✓ Found test env file: $TEST_ENV_FILE"
        break
    fi
done

if [ -z "$TEST_ENV_FILE" ]; then
    echo "⚠️  No test env file found, using base .env only"
fi

# Start new log collector
echo ""
echo "🚀 Starting new log collector..."

if [ -n "$TEST_ENV_FILE" ]; then
    # With test env file
    nohup docker compose \
        --env-file .env \
        --env-file "$TEST_ENV_FILE" \
        -f infrastructure/compose/docker-compose.yml \
        -f infrastructure/compose/docker-compose.prod.yml \
        logs -f --timestamps >> "$TEST_LOG_DIR/all-services.log" 2> "$TEST_LOG_DIR/log-collector.err" &
else
    # Without test env file
    nohup docker compose \
        -f infrastructure/compose/docker-compose.yml \
        -f infrastructure/compose/docker-compose.prod.yml \
        logs -f --timestamps >> "$TEST_LOG_DIR/all-services.log" 2> "$TEST_LOG_DIR/log-collector.err" &
fi

NEW_PID=$!
echo $NEW_PID > "$TEST_LOG_DIR/log-collector.pid"
echo "✓ Started new log collector (PID: $NEW_PID)"

# Wait for logs to start flowing
echo ""
echo "⏳ Waiting for logs to start flowing..."
sleep 3

# Verify it's working
echo ""
echo "✅ Verification:"
if ps -p $NEW_PID > /dev/null 2>&1; then
    echo "  ✓ Process is running (PID: $NEW_PID)"
else
    echo "  ❌ Process died immediately! Check errors:"
    cat "$TEST_LOG_DIR/log-collector.err"
    exit 1
fi

# Check if log file is receiving data
if [ -s "$TEST_LOG_DIR/all-services.log" ]; then
    LINE_COUNT=$(wc -l < "$TEST_LOG_DIR/all-services.log")
    FILE_SIZE=$(ls -lh "$TEST_LOG_DIR/all-services.log" | awk '{print $5}')
    echo "  ✓ all-services.log is receiving data ($LINE_COUNT lines, $FILE_SIZE)"
    echo ""
    echo "📋 First 10 lines:"
    head -10 "$TEST_LOG_DIR/all-services.log"
else
    echo "  ⚠️  all-services.log is still empty, checking for errors..."
    if [ -s "$TEST_LOG_DIR/log-collector.err" ]; then
        echo ""
        echo "❌ Errors found:"
        cat "$TEST_LOG_DIR/log-collector.err"
        exit 1
    else
        echo "  No errors in log-collector.err. It may just need more time."
        echo "  Wait 10 seconds and check: tail -f $TEST_LOG_DIR/all-services.log"
    fi
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "✅ FIX COMPLETE"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "📁 Log directory: $TEST_LOG_DIR"
echo "🔄 Collector PID: $NEW_PID"
echo ""
echo "💡 To verify logs are collecting:"
echo "   tail -f $TEST_LOG_DIR/all-services.log"
echo ""
echo "💡 To check for errors:"
echo "   cat $TEST_LOG_DIR/log-collector.err"
echo ""
echo "💡 To monitor log growth:"
echo "   watch -n 5 'ls -lh $TEST_LOG_DIR/all-services.log'"
