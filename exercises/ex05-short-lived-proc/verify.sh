#!/bin/bash
# verify.sh — Exercise 5: Short-lived process capture
# Runs bpftrace to capture exec events, executes the trigger,
# and checks that the short-lived process name appears at least 3 times.
set -u
cd "$(dirname "$0")"

OUT=$(mktemp)
bpftrace -e 'tracepoint:sched:sched_process_exec /comm == "ex05_slp"/ { printf("exec: pid=%d comm=%s\n", args->pid, comm); }' > "$OUT" 2>&1 &
BPID=$!
sleep 1.5
bash trigger.sh
sleep 0.5
kill -INT "$BPID" 2>/dev/null || true
wait "$BPID" 2>/dev/null || true

COUNT=$(grep -c 'ex05_slp' "$OUT" 2>/dev/null || echo "0")

if [ "$COUNT" -ge 3 ]; then
    echo "PASS: ex05-short-lived-proc (count=$COUNT)"
    rm -f "$OUT"
    exit 0
else
    echo "FAIL: ex05-short-lived-proc (expected >= 3, got $COUNT)"
    cat "$OUT"
    rm -f "$OUT"
    exit 1
fi
