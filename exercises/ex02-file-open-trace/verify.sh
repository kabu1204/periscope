#!/bin/bash
# verify.sh — Exercise 2: File-open tracing
# Runs bpftrace with the reference command, executes the trigger,
# and checks that the expected file path appears in the output.
set -u
cd "$(dirname "$0")"

OUT=$(mktemp)
bpftrace -e 'tracepoint:syscalls:sys_enter_openat /comm == "ex02_trigger"/ { printf("%s\n", str(args->filename)); }' > "$OUT" 2>&1 &
BPID=$!
sleep 1.5
bash trigger.sh
sleep 0.5
kill -INT "$BPID" 2>/dev/null || true
wait "$BPID" 2>/dev/null || true

if grep -q '/tmp/ex02_marker_file' "$OUT"; then
    echo "PASS: ex02-file-open-trace"
    rm -f "$OUT"
    exit 0
else
    echo "FAIL: ex02-file-open-trace (expected /tmp/ex02_marker_file in output)"
    cat "$OUT"
    rm -f "$OUT"
    exit 1
fi
