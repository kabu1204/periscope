#!/bin/bash
# attribution_biolat.sh — M4 case study: show block IO latency rises under
# the injected anomaly.
#
# Captures biolat during a baseline run and during an anomaly run, computes
# the median bucket of each, and asserts the anomaly median is higher.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BIOLAT="$PROJECT_DIR/tools/biolat/target/release/biolat"
TRACE_SECS=12

[ -x "$BIOLAT" ] || (cd "$PROJECT_DIR/tools/biolat" && cargo build --release)

# Median bucket lower bound from a biolat histogram.
median_bucket() {
    awk '
    /[0-9]+ -> [0-9]+/ {
        lo = $1 + 0
        for (i = 1; i <= NF; i++) if ($i == ":") { c = $(i+1) + 0; break }
        print lo, c
    }' "$1" | sort -n | awk '
    { cum += $2; rows[NR] = $1; cnt[NR] = $2; total += $2 }
    END {
        half = total / 2; cum = 0
        for (i = 1; i <= NR; i++) {
            cum += cnt[i]
            if (cum >= half) { print rows[i]; exit }
        }
    }'
}

echo "=== baseline ==="
BASE=$(mktemp)
"$BIOLAT" -d "$TRACE_SECS" > "$BASE" 2>/dev/null &
PID=$!
sleep 1
bash "$SCRIPT_DIR/run_baseline.sh" /var/tmp/m4_bench.db 2200 >/dev/null
wait "$PID"
BASE_MED=$(median_bucket "$BASE")
echo "baseline median bucket: ${BASE_MED}us"

echo "=== anomaly (background writer injected) ==="
ANOM=$(mktemp)
"$BIOLAT" -d "$TRACE_SECS" > "$ANOM" 2>/dev/null &
PID=$!
sleep 1
bash "$SCRIPT_DIR/run_anomaly.sh" 2200 10 >/dev/null
wait "$PID"
ANOM_MED=$(median_bucket "$ANOM")
echo "anomaly median bucket: ${ANOM_MED}us"

echo "=== biolat anomaly histogram ==="
grep ' -> ' "$ANOM"

rm -f "$BASE" "$ANOM"

if [ "$ANOM_MED" -gt "$BASE_MED" ]; then
    echo "ATTRIBUTED: block IO median latency rose under the anomaly (${BASE_MED}us -> ${ANOM_MED}us)"
else
    echo "NOT ATTRIBUTED: anomaly median (${ANOM_MED}us) did not exceed baseline (${BASE_MED}us)" >&2
    exit 1
fi
