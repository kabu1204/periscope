#!/bin/bash
# verify.sh — Exercise 7: Signal delivery tracing
# Runs bpftrace to trace signal generation, executes the trigger,
# and checks that SIGUSR1 (signal 10) appears at least 5 times.
set -u
cd "$(dirname "$0")"

OUT=$(mktemp)
bpftrace -e 'tracepoint:signal:signal_generate /comm == "ex07_trigger"/ { printf("sig=%d pid=%d\n", args->sig, args->pid); }' > "$OUT" 2>&1 &
BPID=$!
sleep 1.5
bash trigger.sh
sleep 0.5
kill -INT "$BPID" 2>/dev/null || true
wait "$BPID" 2>/dev/null || true

COUNT=$(grep -c 'sig=10' "$OUT" 2>/dev/null || echo "0")

if [ "$COUNT" -ge 5 ]; then
    echo "PASS: ex07-signal-delivery (count=$COUNT)"
    rm -f "$OUT"
    exit 0
else
    echo "FAIL: ex07-signal-delivery (expected >= 5 sig=10, got $COUNT)"
    cat "$OUT"
    rm -f "$OUT"
    exit 1
fi
