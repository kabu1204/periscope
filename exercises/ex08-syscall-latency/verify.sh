#!/bin/bash
# verify.sh — Exercise 8: Syscall latency histogram
# Runs bpftrace with openat enter/exit timing, executes the trigger,
# and checks that a @latency histogram with data is produced.
set -u
cd "$(dirname "$0")"

OUT=$(mktemp)
bpftrace -e '
tracepoint:syscalls:sys_enter_openat /comm == "ex08_trigger"/ { @start[tid] = nsecs; }
tracepoint:syscalls:sys_exit_openat /comm == "ex08_trigger" && @start[tid]/ {
    @latency = hist(nsecs - @start[tid]);
    delete(@start[tid]);
}
' > "$OUT" 2>&1 &
BPID=$!
sleep 1.5
bash trigger.sh
sleep 0.5
kill -INT "$BPID" 2>/dev/null || true
wait "$BPID" 2>/dev/null || true

if grep -q '@latency' "$OUT" && grep -qP '\d+\s+\|' "$OUT"; then
    echo "PASS: ex08-syscall-latency"
    rm -f "$OUT"
    exit 0
else
    echo "FAIL: ex08-syscall-latency (no @latency histogram found)"
    cat "$OUT"
    rm -f "$OUT"
    exit 1
fi
