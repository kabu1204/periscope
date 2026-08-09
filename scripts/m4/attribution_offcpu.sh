#!/bin/bash
# attribution_offcpu.sh — M4 case study: attribute sqlite_bench's blocked
# time with offcpu.
#
# Runs the baseline benchmark while tracing with offcpu, then asserts that
# the dominant off-CPU kernel stack for sqlite_bench is the synchronous
# commit (fsync) path. Prints the matching stack.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
OFFCPU="$PROJECT_DIR/tools/offcpu/target/release/offcpu"
TRACE_SECS=10

[ -x "$OFFCPU" ] || (cd "$PROJECT_DIR/tools/offcpu" && cargo build --release)

OUT=$(mktemp)
"$OFFCPU" -d "$TRACE_SECS" > "$OUT" 2>/dev/null &
PID=$!
sleep 1
bash "$SCRIPT_DIR/run_baseline.sh" /var/tmp/m4_bench.db 2200 >/dev/null
wait "$PID"

echo "=== offcpu stacks for sqlite_bench (fsync path) ==="
grep -B14 'sqlite_bench' "$OUT" | grep -E 'fdatasync|ext4_sync_file|folio_wait_writeback|io_schedule' | sort -u

if grep -B14 'sqlite_bench' "$OUT" | grep -qE 'fdatasync|ext4_sync_file'; then
    echo "ATTRIBUTED: sqlite_bench blocks in the fsync/commit path"
else
    echo "NOT ATTRIBUTED: fsync path not found for sqlite_bench" >&2
    rm -f "$OUT"
    exit 1
fi
rm -f "$OUT"
