# STATE.md — Project Status (Agent Must Read/Write Every Session)

> This file is maintained by the agent. Read at the start of each session, update at the end. Fixed format as follows.

## Current Position

- Current milestone: **M1 complete — awaiting user confirmation**
- Status: All M1 deliverables done; `ci_report.sh m1` passes (8/8 exercises). Combined M0+M1: 12/12 checks pass.

## Previous Session Summary

M1 was completed in this session:

1. **bpftrace installed**: v0.23.2 via apt on Debian 13 trixie. Also installed bpftool.

2. **Tutorial written** (`docs/M1-tutorial.md`): covers eBPF program model (event sources, maps, verifier), bpftrace syntax, probe types (kprobe/uprobe/tracepoint/USDT), aggregations (count/hist/lhist), arg access, timing pattern, and practical workflow.

3. **8 exercises created** under `exercises/`:
   - ex01: syscall counting (openat count = 10)
   - ex02: file-open tracing (filename in output)
   - ex03: block IO latency (histogram)
   - ex04: scheduling latency (histogram)
   - ex05: short-lived process capture (exec tracepoint)
   - ex06: user-space uprobe (malloc count = 100)
   - ex07: signal delivery (sig=10 × 5)
   - ex08: syscall latency (enter/exit histogram)

4. **Static linking**: trigger programs for exercises 1, 2, 5, 8 use `-static` compilation to ensure deterministic syscall counts and reliable `str()` filename reading. Dynamically-linked binaries produced extra `openat` calls from `ld.so` and `str()` failures on some user-space addresses.

5. **Binary name length**: exercise 5's binary name shortened from `ex05_shortlived_proc` (20 chars) to `ex05_slp` (8 chars) to fit the 16-char kernel `comm` field.

6. **Documentation**: `docs/M1-design.md` (design note), `checkpoints/M1.md` (checkpoint report).

## Next Steps

1. **User confirmation**: Review M1 deliverables and checkpoint report. Confirm to proceed to M2.
2. **M2.0 preparation**: finalize D-001 (libbpf-rs vs. aya) in `DECISIONS.md`. Set up `rust-toolchain.toml` with `rustfmt` and `clippy`.
3. **Manual exercise**: user should complete the bpftrace exercises following the tutorial.
4. **TrueNAS**: when accessible, re-probe and add to monitoring stack.

## Open Questions

- TrueNAS SCALE machine accessibility (not reachable since M0).
- D-001 library selection (libbpf-rs vs. aya) — both viable, decision needed before M2.

## Recent Update

- Date: 2026-08-09
- Updated by: Agent (M1 session)
