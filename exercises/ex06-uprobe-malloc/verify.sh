#!/bin/bash
# verify.sh — Exercise 6: User-space uprobe on malloc
# Runs bpftrace with a uprobe on libc:malloc, executes the trigger,
# and checks that the malloc count is exactly 100.
set -u
cd "$(dirname "$0")"

LIBC_PATH=$(ldd /bin/ls 2>/dev/null | grep 'libc.so.6' | awk '{print $3}')
if [ -z "$LIBC_PATH" ]; then
    LIBC_PATH="/lib/x86_64-linux-gnu/libc.so.6"
fi

OUT=$(mktemp)
bpftrace -e "uprobe:${LIBC_PATH}:malloc /comm == \"ex06_trigger\"/ { @count = count(); }" > "$OUT" 2>&1 &
BPID=$!
sleep 1.5
bash trigger.sh
sleep 0.5
kill -INT "$BPID" 2>/dev/null || true
wait "$BPID" 2>/dev/null || true

COUNT=$(grep -oP '@count:\s+\K\d+' "$OUT" 2>/dev/null || echo "0")

if [ "$COUNT" -eq 100 ]; then
    echo "PASS: ex06-uprobe-malloc (count=$COUNT)"
    rm -f "$OUT"
    exit 0
else
    echo "FAIL: ex06-uprobe-malloc (expected 100, got $COUNT)"
    cat "$OUT"
    rm -f "$OUT"
    exit 1
fi
