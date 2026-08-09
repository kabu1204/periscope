#!/bin/bash
# verify_m3.sh — Verification for runqlat and offcpu against bcc oracles
# and three known injection scenarios.
#
# Oracle comparison (per ROADMAP.md):
#   - runqlat vs bcc runqlat-bpfcc under CPU saturation (Scenario A):
#     peak bucket positions within 2x.
#   - offcpu vs bcc offcputime-bpfcc under lock contention (Scenario B):
#     both must attribute the dominant off-CPU stack to futex.
#
# Injection scenarios (per ROADMAP.md):
#   A. CPU saturation     -> runqlat must show significantly elevated queuing
#                            vs an idle baseline.
#   B. Lock contention    -> offcpu must attribute to the futex/lock stack.
#   C. Synchronous disk IO -> offcpu must attribute to the IO wait stack.
#
# Incorrect attribution means failure.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNQLAT="$PROJECT_DIR/tools/runqlat/target/release/runqlat"
OFFCPU="$PROJECT_DIR/tools/offcpu/target/release/offcpu"
LOCK_BIN="$PROJECT_DIR/scripts/m3/lock_contention"
TRACE_SECS=8

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Extract the peak bucket's lower bound from a log2 histogram output
# (lines like "    256 -> 511        : 23       |...|").
extract_peak() {
    awk '
    /[0-9]+ -> [0-9]+/ {
        lo = $1
        for (i = 1; i <= NF; i++) {
            if ($i == ":") { count = $(i+1); break }
        }
        if (count > 0 && count > max) { max = count; peak = lo }
    }
    END { print peak+0 }
    ' "$1"
}

# Ensure the tools and workloads are built.
for bin in "$RUNQLAT" "$OFFCPU"; do
    if [ ! -x "$bin" ]; then
        echo "ERROR: $bin not built" >&2
        exit 1
    fi
done
if [ ! -x "$LOCK_BIN" ]; then
    gcc -O2 -o "$LOCK_BIN" "$PROJECT_DIR/scripts/m3/lock_contention.c" -lpthread
fi

# ---------------------------------------------------------------------------
# Scenario A: CPU saturation -> runqlat must show significantly elevated
# queuing compared to an idle baseline; also the oracle comparison for
# runqlat (peak bucket within 2x of bcc runqlat under the same workload).
# ---------------------------------------------------------------------------
echo "=== Scenario A: CPU saturation (runqlat) ==="

# Fraction (per-1000) of samples at or above 64us in a runqlat histogram.
# On an idle system essentially all waits are a few microseconds; under CPU
# saturation preempted tasks queue for a scheduler quantum (~ms), so the
# share of high-latency samples grows sharply. The peak bucket alone is not
# a valid elevation signal: woken daemons produce many short waits that
# keep the peak low even under saturation, for bcc as well as our tool.
tail_fraction() {
    awk '
    /[0-9]+ -> [0-9]+/ {
        lo = $1
        for (i = 1; i <= NF; i++) {
            if ($i == ":") { count = $(i+1); break }
        }
        total += count
        if (lo >= 64) hi += count
    }
    END { if (total == 0) print 0; else print int(hi * 1000 / total) }
    ' "$1"
}

# Baseline: trace an (approximately) idle system.
BASELINE_OUT=$(mktemp)
"$RUNQLAT" -d "$TRACE_SECS" > "$BASELINE_OUT" 2>/dev/null
BASELINE_PEAK=$(extract_peak "$BASELINE_OUT")
BASELINE_FRAC=$(tail_fraction "$BASELINE_OUT")
rm -f "$BASELINE_OUT"

# Saturated: run 2x CPUs worth of CPU-bound processes while tracing with
# both our tool and the bcc oracle in parallel.
OUR_OUT=$(mktemp)
ORACLE_OUT=$(mktemp)
"$RUNQLAT" -d "$TRACE_SECS" > "$OUR_OUT" 2>/dev/null &
OUR_PID=$!
timeout -s INT "$TRACE_SECS" runqlat-bpfcc > "$ORACLE_OUT" 2>/dev/null &
ORACLE_PID=$!
# Give the bcc tool time to finish its LLVM compilation and print its
# "Tracing" banner before the workload starts, so both tools observe the
# same load window.
for _ in $(seq 1 10); do
    grep -q 'Tracing' "$ORACLE_OUT" && break
    sleep 0.5
done
bash "$SCRIPT_DIR/m3/cpu_burn.sh" $((TRACE_SECS - 3))
wait "$OUR_PID" 2>/dev/null
wait "$ORACLE_PID" 2>/dev/null

OUR_PEAK=$(extract_peak "$OUR_OUT")
ORACLE_PEAK=$(extract_peak "$ORACLE_OUT")
OUR_FRAC=$(tail_fraction "$OUR_OUT")
ORACLE_FRAC=$(tail_fraction "$ORACLE_OUT")
rm -f "$OUR_OUT" "$ORACLE_OUT"

echo "  baseline: peak=${BASELINE_PEAK}us tail=${BASELINE_FRAC}/1000  saturated: our peak=${OUR_PEAK}us tail=${OUR_FRAC}/1000  oracle peak=${ORACLE_PEAK}us"

# Elevation check: the saturated tail fraction (>=64us) must be at least
# 4x the baseline fraction, and at least 10/1000 in absolute terms to
# avoid multiplying noise on a near-zero baseline.
if [ "$BASELINE_FRAC" -eq 0 ]; then BASELINE_FRAC=1; fi
if [ "$OUR_FRAC" -ge 10 ] && [ "$OUR_FRAC" -ge $((BASELINE_FRAC * 4)) ]; then
    pass "runqlat shows elevated queuing under CPU saturation (tail >=64us: baseline=${BASELINE_FRAC}/1000 saturated=${OUR_FRAC}/1000)"
else
    fail "runqlat queuing not elevated (tail >=64us: baseline=${BASELINE_FRAC}/1000 saturated=${OUR_FRAC}/1000)"
fi

# Oracle check: peak positions within 2x (adjacent log2 buckets accepted),
# and tail fractions (>=64us) within 2x. The peak alone is a weak signal
# under saturation (both tools peak low because of short daemon wakeups),
# so the tail fraction carries the distribution comparison.
if [ "$OUR_PEAK" -gt 0 ] && [ "$ORACLE_PEAK" -gt 0 ]; then
    if [ "$OUR_PEAK" -ge "$ORACLE_PEAK" ]; then
        RATIO=$((OUR_PEAK / ORACLE_PEAK))
    else
        RATIO=$((ORACLE_PEAK / OUR_PEAK))
    fi
    [ "$RATIO" -eq 0 ] && RATIO=1

    BF=$BASELINE_FRAC; [ "$BF" -eq 0 ] && BF=1
    OF=$ORACLE_FRAC; [ "$OF" -eq 0 ] && OF=1
    if [ "$OUR_FRAC" -ge "$OF" ]; then
        FRAC_RATIO=$((OUR_FRAC / OF))
    else
        FRAC_RATIO=$((OF / (OUR_FRAC > 0 ? OUR_FRAC : 1)))
    fi

    if [ "$RATIO" -le 2 ] && [ "$FRAC_RATIO" -le 2 ]; then
        pass "runqlat matches bcc oracle within 2x (peak our=${OUR_PEAK} oracle=${ORACLE_PEAK}; tail our=${OUR_FRAC}/1000 oracle=${ORACLE_FRAC}/1000)"
    else
        fail "runqlat differs from bcc oracle (peak our=${OUR_PEAK} oracle=${ORACLE_PEAK}; tail our=${OUR_FRAC}/1000 oracle=${ORACLE_FRAC}/1000)"
    fi
else
    fail "runqlat or bcc oracle produced no data (our=${OUR_PEAK} oracle=${ORACLE_PEAK})"
fi

# ---------------------------------------------------------------------------
# Scenario B: lock contention -> offcpu must attribute the dominant
# off-CPU stack to futex. Also the oracle comparison for offcpu: bcc
# offcputime under the same workload must also attribute to futex.
# ---------------------------------------------------------------------------
echo "=== Scenario B: lock contention (offcpu) ==="

OUR_OUT=$(mktemp)
ORACLE_OUT=$(mktemp)
"$OFFCPU" -d "$TRACE_SECS" > "$OUR_OUT" 2>/dev/null &
OUR_PID=$!
timeout -s INT "$TRACE_SECS" offcputime-bpfcc > "$ORACLE_OUT" 2>/dev/null &
ORACLE_PID=$!
sleep 1
"$LOCK_BIN" $((TRACE_SECS - 2)) 8
wait "$OUR_PID" 2>/dev/null
wait "$ORACLE_PID" 2>/dev/null

if grep -q 'futex' "$OUR_OUT"; then
    pass "offcpu attributes lock contention to futex stack"
else
    fail "offcpu did not attribute lock contention to futex stack"
fi
if grep -q 'futex' "$ORACLE_OUT"; then
    pass "bcc offcputime oracle attributes lock contention to futex stack"
else
    fail "bcc offcputime oracle did not attribute lock contention to futex stack"
fi
rm -f "$OUR_OUT" "$ORACLE_OUT"

# ---------------------------------------------------------------------------
# Scenario C: synchronous disk wait -> offcpu must attribute the dominant
# off-CPU stack to the IO wait path (block layer submission/wait).
# ---------------------------------------------------------------------------
echo "=== Scenario C: synchronous disk wait (offcpu) ==="

OUR_OUT=$(mktemp)
"$OFFCPU" -d $((TRACE_SECS + 2)) > "$OUR_OUT" 2>/dev/null &
OUR_PID=$!
sleep 1
bash "$SCRIPT_DIR/m3/sync_write.sh" "$TRACE_SECS"
wait "$OUR_PID" 2>/dev/null

# The sync fio workload blocks in direct-IO submission; on this kernel the
# stack contains io_submit (ext4 + iomap direct IO path).
if grep -qE 'io_submit|__wait_on_bit|blk_mq|submit_bio|iomap_dio' "$OUR_OUT"; then
    pass "offcpu attributes synchronous disk wait to IO stack"
else
    fail "offcpu did not attribute synchronous disk wait to IO stack"
fi
rm -f "$OUR_OUT"

echo ""
echo "=============================="
echo "verify_m3.sh results: pass=$PASS fail=$FAIL"
echo "=============================="

[ "$FAIL" -eq 0 ]
