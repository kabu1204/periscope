#!/bin/bash
# trigger.sh — Exercise 4: Scheduling latency
# Spawns CPU-bound processes to create scheduling activity (wakeups and context switches).
set -eu
cd "$(dirname "$0")"

# Start 4 CPU-bound processes to create contention
yes_pids=""
for i in $(seq 1 4); do
    yes > /dev/null 2>&1 &
    yes_pids="$yes_pids $!"
done

# Let them run for 2 seconds to generate scheduling events
sleep 2

# Clean up
for pid in $yes_pids; do
    kill "$pid" 2>/dev/null || true
done
wait 2>/dev/null || true
