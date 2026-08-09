#!/bin/bash
# verify.sh — Exercise 4: Scheduling latency histogram
# Runs bpftrace with scheduling latency tracking, executes a CPU contention trigger,
# and checks that a @latency histogram with data is produced.
set -u
cd "$(dirname "$0")"

OUT=$(mktemp)
bpftrace -e '
tracepoint:sched:sched_wakeup { @start[args->pid] = nsecs; }
tracepoint:sched:sched_switch /@start[args->next_pid]/ {
    @latency = hist(nsecs - @start[args->next_pid]);
    delete(@start[args->next_pid]);
}
' > "$OUT" 2>&1 &
BPID=$!
sleep 1.5
bash trigger.sh
sleep 1
kill -INT "$BPID" 2>/dev/null || true
wait "$BPID" 2>/dev/null || true

if grep -q '@latency' "$OUT" && grep -qP '\d+\s+\|' "$OUT"; then
    echo "PASS: ex04-sched-latency"
    rm -f "$OUT"
    exit 0
else
    echo "FAIL: ex04-sched-latency (no @latency histogram found)"
    cat "$OUT"
    rm -f "$OUT"
    exit 1
fi
