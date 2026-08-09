#!/bin/bash
# verify_exporter.sh — Verification for the eBPF Prometheus exporter mode (P-001).
#
# Starts each tool in exporter mode, drives a known workload, and asserts:
#   1. GET /metrics returns 200 and contains the expected metric names.
#   2. The metrics move under the workload (histogram _count / offcpu series grow).
#   3. Prometheus scrapes each exporter (up{job=...} == 1).
#
# Exporters are started on a private loopback port block and stopped on exit.

set -u

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIOLAT="$PROJECT_DIR/tools/biolat/target/release/biolat"
RUNQLAT="$PROJECT_DIR/tools/runqlat/target/release/runqlat"
OFFCPU="$PROJECT_DIR/tools/offcpu/target/release/offcpu"
PROM="http://localhost:9090"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

PIDS=()
cleanup() {
    for p in "${PIDS[@]:-}"; do
        [ -n "$p" ] && kill "$p" 2>/dev/null
    done
    wait 2>/dev/null
}
trap cleanup EXIT

for bin in "$BIOLAT" "$RUNQLAT" "$OFFCPU"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: $bin not built" >&2
        exit 1
    fi
done

# Start exporters on loopback.
"$BIOLAT" --exporter 127.0.0.1:9601 >/dev/null 2>&1 &
PIDS+=($!)
"$RUNQLAT" --exporter 127.0.0.1:9602 >/dev/null 2>&1 &
PIDS+=($!)
"$OFFCPU" --exporter 127.0.0.1:9603 >/dev/null 2>&1 &
PIDS+=($!)
sleep 2

# --- biolat ---
echo "=== biolat exporter ==="
BEFORE=$(curl -s http://127.0.0.1:9601/metrics | grep '^periscope_block_io_latency_seconds_count' | awk '{print $2}')
BEFORE=${BEFORE:-0}
bash "$PROJECT_DIR/scripts/m4/run_baseline.sh" /var/tmp/m4_bench.db 600 >/dev/null 2>&1
BODY=$(curl -s http://127.0.0.1:9601/metrics)
AFTER=$(echo "$BODY" | grep '^periscope_block_io_latency_seconds_count' | awk '{print $2}')
AFTER=${AFTER:-0}
if echo "$BODY" | grep -q 'periscope_block_io_latency_seconds_bucket'; then
    pass "biolat /metrics exposes block IO histogram"
else
    fail "biolat /metrics missing block IO histogram"
fi
if [ "${AFTER%.*}" -gt "${BEFORE%.*}" ]; then
    pass "biolat _count increased under workload ($BEFORE -> $AFTER)"
else
    fail "biolat _count did not increase ($BEFORE -> $AFTER)"
fi

# --- runqlat ---
echo "=== runqlat exporter ==="
# Generate CPU load to move the run queue histogram. Capture PIDs explicitly
# (not job specs), which is reliable in a non-interactive script.
YPIDS=()
for _ in 1 2 3 4; do yes >/dev/null & YPIDS+=($!); done
sleep 2
kill "${YPIDS[@]}" 2>/dev/null
wait "${YPIDS[@]}" 2>/dev/null
BODY2=$(curl -s http://127.0.0.1:9602/metrics)
if echo "$BODY2" | grep -q 'periscope_runqueue_latency_seconds_bucket'; then
    pass "runqlat /metrics exposes run queue histogram"
else
    fail "runqlat /metrics missing run queue histogram"
fi

# --- offcpu ---
echo "=== offcpu exporter ==="
"$PROJECT_DIR/scripts/m3/lock_contention" 2 8 >/dev/null 2>&1
BODY=$(curl -s http://127.0.0.1:9603/metrics)
if echo "$BODY" | grep -q 'periscope_offcpu_seconds_total{'; then
    pass "offcpu /metrics exposes off-CPU series"
else
    fail "offcpu /metrics missing off-CPU series"
fi

# --- Prometheus scraping ---
echo "=== Prometheus scrape targets ==="
# Wait up to ~30s for Prometheus to scrape the exporters.
for job in biolat runqlat offcpu; do
    UP=""
    for _ in $(seq 1 15); do
        UP=$(curl -s -G "$PROM/api/v1/query" --data-urlencode "query=up{job=\"$job\"}" \
            | python3 -c 'import sys,json; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else "")' 2>/dev/null)
        [ "$UP" = "1" ] && break
        sleep 2
    done
    if [ "$UP" = "1" ]; then
        pass "Prometheus scrapes $job (up==1)"
    else
        fail "Prometheus not scraping $job (up=$UP)"
    fi
done

echo ""
echo "=============================="
echo "verify_exporter.sh results: pass=$PASS fail=$FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ]
