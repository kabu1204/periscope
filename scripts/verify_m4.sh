#!/bin/bash
# verify_m4.sh — M4 case study smoke regression.
#
# Re-runs each conclusion of docs/M4-case-study.md and asserts it holds:
#   1. Baseline throughput exceeds anomaly throughput.
#   2. offcpu attributes sqlite_bench to the fsync/commit path.
#   3. biolat anomaly median exceeds baseline median.
#   4. runqlat shows no CPU-saturation elevation during the benchmark.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
M4="$SCRIPT_DIR/m4"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

rows_sec() { echo "$1" | grep -oE 'rows_per_sec=[0-9]+' | cut -d= -f2; }

echo "=== Conclusion 1: anomaly slows throughput ==="
BASE_OUT=$(bash "$M4/run_baseline.sh" /var/tmp/m4_bench.db 2200)
BASE_RPS=$(rows_sec "$BASE_OUT")
ANOM_OUT=$(bash "$M4/run_anomaly.sh" 2200 12)
ANOM_RPS=$(rows_sec "$ANOM_OUT")
echo "  baseline=${BASE_RPS} rows/sec  anomaly=${ANOM_RPS} rows/sec"
if [ "$BASE_RPS" -gt "$ANOM_RPS" ]; then
    pass "anomaly throughput (${ANOM_RPS}) below baseline (${BASE_RPS})"
else
    fail "anomaly throughput (${ANOM_RPS}) not below baseline (${BASE_RPS})"
fi

echo "=== Conclusion 2: fsync attribution (offcpu) ==="
if bash "$M4/attribution_offcpu.sh" >/dev/null 2>&1; then
    pass "offcpu attributes sqlite_bench to the fsync/commit path"
else
    fail "offcpu did not attribute sqlite_bench to the fsync/commit path"
fi

echo "=== Conclusion 3: block IO latency rises (biolat) ==="
if bash "$M4/attribution_biolat.sh" >/dev/null 2>&1; then
    pass "biolat anomaly median exceeds baseline median"
else
    fail "biolat anomaly median did not exceed baseline median"
fi

echo "=== Conclusion 4: no CPU saturation (runqlat) ==="
RUNQLAT="$PROJECT_DIR/tools/runqlat/target/release/runqlat"
RQ_OUT=$(mktemp)
"$RUNQLAT" -d 8 > "$RQ_OUT" 2>/dev/null &
PID=$!
sleep 1
bash "$M4/run_baseline.sh" /var/tmp/m4_bench.db 1500 >/dev/null
wait "$PID"
TAIL=$(awk '/[0-9]+ -> [0-9]+/ { lo=$1; for(i=1;i<=NF;i++) if($i==":"){c=$(i+1);break} total+=c; if(lo>=64) hi+=c } END{ print (total? int(hi*1000/total) : 0) }' "$RQ_OUT")
rm -f "$RQ_OUT"
echo "  runqlat tail (>=64us) fraction during benchmark: ${TAIL}/1000"
# A saturated system shows >=100/1000; the fsync-bound benchmark does not.
if [ "$TAIL" -lt 100 ]; then
    pass "runqlat shows no CPU-saturation elevation (${TAIL}/1000 < 100/1000)"
else
    fail "runqlat shows elevated queuing (${TAIL}/1000), unexpected for fsync-bound workload"
fi

echo ""
echo "=============================="
echo "verify_m4.sh results: pass=$PASS fail=$FAIL"
echo "=============================="
[ "$FAIL" -eq 0 ]
