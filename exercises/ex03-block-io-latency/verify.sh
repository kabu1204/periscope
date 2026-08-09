#!/bin/bash
# verify.sh — Exercise 3: Block IO latency histogram
# Runs bpftrace with block IO latency tracking, executes a dd trigger,
# and checks that a @latency histogram with data is produced.
set -u
cd "$(dirname "$0")"

OUT=$(mktemp)
bpftrace -e '
tracepoint:block:block_rq_issue { @start[args->sector] = nsecs; }
tracepoint:block:block_rq_complete /@start[args->sector]/ {
    @latency = hist(nsecs - @start[args->sector]);
    delete(@start[args->sector]);
}
' > "$OUT" 2>&1 &
BPID=$!
sleep 1.5
bash trigger.sh
sleep 1
kill -INT "$BPID" 2>/dev/null || true
wait "$BPID" 2>/dev/null || true

if grep -q '@latency' "$OUT" && grep -qP '\d+\s+\|' "$OUT"; then
    echo "PASS: ex03-block-io-latency"
    rm -f "$OUT"
    exit 0
else
    echo "FAIL: ex03-block-io-latency (no @latency histogram found)"
    cat "$OUT"
    rm -f "$OUT"
    exit 1
fi
