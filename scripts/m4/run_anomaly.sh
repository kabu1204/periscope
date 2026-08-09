#!/bin/bash
# run_anomaly.sh — M4 case study: sqlite insert run with an injected
# block-IO latency anomaly.
#
# A background fio job saturates vda with high queue-depth random writes,
# inflating block IO completion latency. The sqlite benchmark runs on top
# and its per-commit fsync becomes slower. The case study shows that
# node_exporter metrics (disk util %, write rate) cannot explain the
# slowdown, while biolat/offcpu attribute it to elevated block IO latency.
#
# The fio anomaly file and the database both live on /var/tmp (ext4 on vda),
# a block-backed filesystem; /tmp is tmpfs and would bypass the block layer.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BENCH="$SCRIPT_DIR/sqlite_bench"
DB="/var/tmp/m4_bench.db"
ANOMALY_FILE="/var/tmp/m4_anomaly"
ROWS="${1:-2500}"
DUR="${2:-12}"

[ -x "$BENCH" ] || gcc -O2 -o "$BENCH" "$SCRIPT_DIR/sqlite_bench.c" -lsqlite3

rm -f "$DB" "$DB-journal" "$ANOMALY_FILE"

# Inject the anomaly: high queue-depth random writes to inflate IO latency.
fio --name=anomaly --filename="$ANOMALY_FILE" --rw=randwrite --bs=4k \
    --size=256M --ioengine=libaio --direct=1 --iodepth=32 \
    --runtime="$DUR" --time_based --output=/dev/null &
ANOMALY_PID=$!
sleep 1

# Run the benchmark on top of the anomaly.
"$BENCH" "$DB" "$ROWS" || true

wait "$ANOMALY_PID" 2>/dev/null || true
rm -f "$DB" "$DB-journal" "$ANOMALY_FILE"
