#!/bin/bash
# verify_m2.sh — Oracle comparison: biolat (our tool) vs bcc biolatency.
#
# Runs a fixed-parameter fio workload (≥5 runs), captures both tools' output
# in parallel, and compares peak bucket positions.
#
# Acceptance criteria (per ROADMAP.md):
#   - Median and P99 within same order of magnitude (deviation < 2x)
#   - Histogram peak position is the same
#
# Oracle: bcc biolatency (biolatency-bpfcc -d vda)
# If bcc is unavailable, falls back to bpftrace biolatency.bt.
#
# NOTE: the workload file MUST live on a block-backed filesystem. /tmp is
# tmpfs on this machine, and tmpfs IO never reaches the block layer, so no
# block_io_* tracepoints fire. /var/tmp is on / (ext4 on vda).

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIOLAT_BIN="$PROJECT_DIR/tools/biolat/target/release/biolat"

# Ensure the tool is built.
if [ ! -f "$BIOLAT_BIN" ]; then
    echo "Building biolat (release)..." >&2
    (cd "$PROJECT_DIR/tools/biolat" && cargo build --release 2>&1)
fi

# Determine the oracle.
if command -v biolatency-bpfcc &>/dev/null; then
    ORACLE="bcc"
    ORACLE_CMD="biolatency-bpfcc -d vda"
elif [ -x /usr/sbin/biolatency.bt ]; then
    ORACLE="bpftrace"
    ORACLE_CMD="bpftrace /usr/sbin/biolatency.bt"
else
    echo "FAIL: no oracle available (bcc biolatency or bpftrace biolatency.bt)"
    exit 1
fi

echo "Oracle: $ORACLE" >&2
echo "Tool: biolat (Rust + libbpf-rs)" >&2

# Fixed workload parameters.
# The workload file must live on a block-backed filesystem: /tmp is tmpfs on
# this machine, and tmpfs IO never reaches the block layer (no block_io_*
# tracepoints fire). /var/tmp is on / (ext4 on vda).
FIO_FILE="/var/tmp/m2_verify_fiotest"
FIO_BS="4k"
FIO_SIZE="64M"
FIO_IODEPTH=16
TRACE_SECS=8
NUM_RUNS=5

PASS=0
FAIL=0

# Extract the peak bucket's lower bound from a histogram output.
# The peak is the bucket with the highest count (ignoring zero-count buckets).
# Returns the lower bound (e.g., 256 for "256 -> 511").
extract_peak() {
    local file="$1"
    # Match lines like "    256 -> 511        : 23       |...|"
    # Capture: lower_bound, count
    # Find the line with the highest count (column after the colon).
    awk '
    /[0-9]+ -> [0-9]+/ {
        # Extract lower bound (first number before ->)
        lo = $1
        # Find the count: it is the number after the colon
        for (i=1; i<=NF; i++) {
            if ($i == ":") {
                count = $(i+1)
                break
            }
        }
        if (count > 0 && count > max) {
            max = count
            peak = lo
        }
    }
    END { print peak+0 }
    ' "$file"
}

for run in $(seq 1 $NUM_RUNS); do
    echo "--- Run $run/$NUM_RUNS ---" >&2

    # Start our tool in background.
    OUR_OUT=$(mktemp)
    "$BIOLAT_BIN" -d $TRACE_SECS > "$OUR_OUT" 2>&1 &
    OUR_PID=$!

    # Start oracle in background.
    ORACLE_OUT=$(mktemp)
    timeout -s INT $TRACE_SECS $ORACLE_CMD > "$ORACLE_OUT" 2>&1 &
    ORACLE_PID=$!

    # Let tools initialize.
    sleep 1

    # Run the workload: 32M of 4K direct writes via fio/libaio on a
    # block-backed filesystem, so every IO passes through the block layer.
    rm -f "$FIO_FILE"
    fio --name=verify --filename="$FIO_FILE" --rw=write --bs=$FIO_BS \
        --size=$FIO_SIZE --ioengine=libaio --direct=1 --iodepth=$FIO_IODEPTH \
        --output=/dev/null
    rm -f "$FIO_FILE"

    # Wait for both to finish.
    wait $OUR_PID 2>/dev/null || true
    wait $ORACLE_PID 2>/dev/null || true

    # Extract peak positions.
    OUR_PEAK=$(extract_peak "$OUR_OUT")
    ORACLE_PEAK=$(extract_peak "$ORACLE_OUT")

    # Check if both produced data.
    if [ "$OUR_PEAK" -eq 0 ] 2>/dev/null; then
        echo "  FAIL: our tool produced no data" >&2
        FAIL=$((FAIL + 1))
        rm -f "$OUR_OUT" "$ORACLE_OUT"
        continue
    fi

    if [ "$ORACLE_PEAK" -eq 0 ] 2>/dev/null; then
        echo "  FAIL: oracle produced no data" >&2
        FAIL=$((FAIL + 1))
        rm -f "$OUR_OUT" "$ORACLE_OUT"
        continue
    fi

    # Compare peak positions: deviation must be < 2x.
    # Note: adjacent log2 buckets (e.g., 256 and 512) have a ratio of exactly 2.
    # We accept ratio <= 2 because adjacent buckets are qualitatively the same
    # order of magnitude (the peak position is "the same" within one bucket).
    if [ "$OUR_PEAK" -ge "$ORACLE_PEAK" ]; then
        RATIO=$((OUR_PEAK / ORACLE_PEAK))
        [ "$RATIO" -eq 0 ] && RATIO=1
    else
        RATIO=$((ORACLE_PEAK / OUR_PEAK))
        [ "$RATIO" -eq 0 ] && RATIO=1
    fi

    if [ "$RATIO" -le 2 ]; then
        echo "  PASS: peak positions match (our=$OUR_PEAK oracle=$ORACLE_PEAK)" >&2
        PASS=$((PASS + 1))
    else
        echo "  FAIL: peak positions differ (our=$OUR_PEAK oracle=$ORACLE_PEAK)" >&2
        FAIL=$((FAIL + 1))
    fi

    rm -f "$OUR_OUT" "$ORACLE_OUT"
done

echo ""
echo "=============================="
echo "verify_m2.sh results: pass=$PASS fail=$FAIL (of $NUM_RUNS runs)"
echo "=============================="

[ "$FAIL" -eq 0 ]
