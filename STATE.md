# STATE.md — Project Status (Agent Must Read/Write Every Session)

> This file is maintained by the agent. Read at the start of each session, update at the end. Fixed format as follows.

## Current Position

- Current milestone: **M2 complete — awaiting user confirmation**
- Status: All M2 deliverables done; `ci_report.sh m2` passes (4/4). Combined M0+M1+M2: 16/16 checks pass.

## Previous Session Summary

M2 was completed in this session:

1. **M2.0 Toolchain setup**: installed Rust 1.97.1 (via rustup), fio, bpfcc-tools, libbpf-dev, clang. Created `rust-toolchain.toml` (stable + rustfmt + clippy). Finalized D-001 (libbpf-rs) in `DECISIONS.md`. Wrote `docs/M2-coding-standards.md`.

2. **biolat tool**: created `tools/biolat/` with:
   - BPF program (`biolat.bpf.c`): attaches to `block_io_start`/`block_io_done` tracepoints, measures IO latency, outputs log2 histogram in microseconds.
   - Userspace (`main.rs`): uses libbpf-rs skeleton API to load/attach BPF programs, reads histogram map, prints bcc-compatible output.
   - Build system: `build.rs` uses `SkeletonBuilder` from libbpf-cargo; `vmlinux.h` generated from kernel BTF.
   - Tracepoint selection: initially used `block_rq_issue`/`block_rq_complete` but sectors didn't match; switched to `block_io_start`/`block_io_done` (same as bcc biolatency on modern kernels).

3. **Verification**: `scripts/verify_m2.sh` runs 5 parallel comparisons between biolat and bcc `biolatency-bpfcc -d vda` under a fixed dd workload. All 5 runs pass (peak positions within 2x). Used `dd oflag=direct` instead of fio because fio with libaio didn't generate block IO tracepoint events on this VM's virtio disk.

4. **CI**: `ci_report.sh` M2 section runs cargo fmt, clippy, build, and oracle comparison. All pass.

5. **Documentation**: `docs/M2-biolat-design.md` (design note), `docs/M2-coding-standards.md`, `checkpoints/M2.md`.

## Next Steps

1. **User confirmation**: Review M2 deliverables and checkpoint report. Confirm to proceed to M3.
2. **M3 preparation**: runqlat and offcpu tools will reuse the libbpf-rs toolchain, vmlinux.h, and build infrastructure from M2.
3. **TrueNAS**: when accessible, re-probe and add to monitoring stack.

## Open Questions

- TrueNAS SCALE machine accessibility (not reachable since M0).
- vmlinux.h management (127K lines checked into git; could be generated at build time in future).

## Recent Update

- Date: 2026-08-09
- Updated by: Agent (M2 session)
