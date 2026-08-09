#!/bin/bash
# cpu_burn.sh — Scenario A workload: CPU saturation.
#
# Spawns 2x as many CPU-bound `yes` processes as there are CPUs,
# for the given duration (seconds). Oversubscription forces runnable
# tasks to wait in the run queue.

set -eu

DUR="${1:-8}"
NCPU=$(nproc)
NPROC=$((NCPU * 2))

pids=()
for _ in $(seq 1 "$NPROC"); do
    yes > /dev/null &
    pids+=($!)
done

sleep "$DUR"

kill "${pids[@]}" 2>/dev/null || true
wait 2>/dev/null || true
