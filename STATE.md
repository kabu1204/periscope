# STATE.md — Project Status (Agent Must Read/Write Every Session)

> This file is maintained by the agent. Read at the start of each session, update at the end. Fixed format as follows.

## Current Position

- Current milestone: **M3 complete — awaiting user confirmation**
- Status: All M3 deliverables done; `ci_report.sh m3` passes (7/7). Combined M0+M1+M2+M3: 23/23 checks pass.

## Previous Session Summary

M2 was reviewed and corrected, then M3 was completed in this session.

**M2 review corrections** (committed):
- Found that the M2 claim "fio/libaio generated no block IO tracepoint events" was wrong: the workload file had been placed in `/tmp`, which is tmpfs — tmpfs IO never reaches the block layer. `verify_m2.sh` now uses fio on `/var/tmp` (block-backed ext4) per the ROADMAP. `checkpoints/M2.md`, `docs/M2-biolat-design.md`, and this file were corrected.

**M3 deliverables**:

1. **`tools/runqlat/`**: run queue latency histogram (equivalent to bcc runqlat). Attaches to `sched_wakeup`, `sched_wakeup_new`, `sched_switch`. Handles preemption (`prev_state == TASK_RUNNING`) like bcc. Log2 histogram in microseconds.

2. **`tools/offcpu/`**: off-CPU time by stack (equivalent to bcc offcputime). Attaches to `sched_switch`; accumulates per (pid, comm, kernel stack, user stack). Kernel stacks symbolized from `/proc/kallsyms`; user addresses raw. Idle task excluded.

3. **`scripts/verify_m3.sh`** + `scripts/m3/` workloads: three injection scenarios —
   - A: CPU saturation → runqlat tail (>=64us) fraction rises >=4x vs baseline; matches bcc runqlat within 2x (peak and tail).
   - B: lock contention (8 threads, one mutex) → offcpu and bcc offcputime both attribute to futex.
   - C: synchronous disk wait (fio sync direct IO) → offcpu attributes to IO wait stack.
   All 5 checks pass.

4. **Docs/CI**: `docs/M3-design.md` (design note), `ci_report.sh` M3 section (fmt, clippy, build for both crates + scenarios), `checkpoints/M3.md`.

## Next Steps

1. **User confirmation**: Review M3 deliverables and checkpoint report. Confirm to proceed to M4.
2. **M4 preparation**: comprehensive case study using biolat/runqlat/offcpu against a real lab workload (candidates: sqlite insert benchmark, fio queue-depth sweep, local inference service CPU-side).
3. **TrueNAS**: when accessible, re-probe and add to monitoring stack.

## Open Questions

- TrueNAS SCALE machine accessibility (not reachable since M0).
- offcpu user-stack symbolization (addresses printed raw; kernel stacks are symbolized). Not required for M3 acceptance.

## Recent Update

- Date: 2026-08-09
- Updated by: Agent (M3 session)
