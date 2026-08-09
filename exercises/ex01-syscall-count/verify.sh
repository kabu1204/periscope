#!/bin/bash
# verify.sh — Exercise 1: Syscall counting
# Runs bpftrace with the reference command, executes the trigger,
# and checks that the openat count is exactly 10.
set -u
cd "$(dirname "$0")"

OUT=$(mktemp)
bpftrace -e 'tracepoint:syscalls:sys_enter_openat /comm == "ex01_trigger"/ { @count = count(); }' > "$OUT" 2>&1 &
BPID=$!
sleep 1.5
bash trigger.sh
sleep 0.5
kill -INT "$BPID" 2>/dev/null || true
wait "$BPID" 2>/dev/null || true

COUNT=$(grep -oP '@count:\s+\K\d+' "$OUT" 2>/dev/null || echo "0")

if [ "$COUNT" -eq 10 ]; then
    echo "PASS: ex01-syscall-count (count=$COUNT)"
    rm -f "$OUT"
    exit 0
else
    echo "FAIL: ex01-syscall-count (expected 10, got $COUNT)"
    cat "$OUT"
    rm -f "$OUT"
    exit 1
fi
