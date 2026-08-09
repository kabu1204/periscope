#!/bin/bash
# trigger.sh — Exercise 3: Block IO latency
# Performs direct I/O writes to generate block IO completions.
set -eu
cd "$(dirname "$0")"

dd if=/dev/zero of=/tmp/ex03_biotest bs=4k count=100 oflag=direct 2>/dev/null
rm -f /tmp/ex03_biotest
