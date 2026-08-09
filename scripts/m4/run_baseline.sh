#!/bin/bash
# run_baseline.sh — M4 case study: baseline sqlite insert run.
#
# Runs the insert benchmark on a block-backed filesystem with no injected
# anomaly. Prints rows/sec. The database file is on /var/tmp (ext4 on vda);
# /tmp is tmpfs and would bypass the block layer entirely.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BENCH="$SCRIPT_DIR/sqlite_bench"
DB="${1:-/var/tmp/m4_bench.db}"
ROWS="${2:-3000}"

[ -x "$BENCH" ] || gcc -O2 -o "$BENCH" "$SCRIPT_DIR/sqlite_bench.c" -lsqlite3

rm -f "$DB" "$DB-journal"
"$BENCH" "$DB" "$ROWS"
rm -f "$DB" "$DB-journal"
