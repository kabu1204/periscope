#!/bin/bash
# sync_write.sh — Scenario C workload: synchronous disk wait.
#
# Performs direct-IO 4K writes to a file on a block-backed filesystem.
# Each write blocks the thread in the block layer until completion,
# producing off-CPU time attributed to the IO wait stack.
#
# The workload file must be on a block-backed filesystem: /tmp is tmpfs
# on this machine, and tmpfs IO never reaches the block layer.

set -eu

SECS="${1:-8}"
FIO_FILE="/var/tmp/m3_syncwrite_test"

fio --name=syncwrite --filename="$FIO_FILE" --rw=write --bs=4k \
    --size=64M --ioengine=sync --direct=1 --iodepth=1 --numjobs=4 \
    --runtime="$SECS" --time_based --output=/dev/null

rm -f "$FIO_FILE"
