# ROADMAP.md — Milestones and Acceptance Criteria (User-Only Modifications)

## Overview

| Milestone | Content | Estimate | Oracle Type |
|-----------|---------|----------|-------------|
| M0 | Environment probing + monitoring stack deployment | 0.5–1 day | Health checks |
| M1 | bpftrace tutorial + exercise set | 1–2 days | Known answers |
| M2 | Custom tool: block IO latency histogram | 2–3 days | bcc comparison |
| M3 | Custom tool: run queue latency + off-CPU | 2–3 days | bcc comparison + injection scenarios |
| M4 | Comprehensive case study | 2–3 days | Reproducible scripts |

User confirmation of the previous milestone's checkpoint report is required before entering the next milestone.

---

## M0 Environment Probing + Monitoring Stack Deployment

**Deliverables**

1. `ENVIRONMENT.md` fully populated: kernel version, BTF availability (`/sys/kernel/btf/vmlinux`), `CONFIG_BPF*` kernel options, CPU/memory/disk models, GPU model (if applicable), and container runtime version for both machines.
2. docker compose monitoring stack: Prometheus (or VictoriaMetrics), Grafana, node_exporter, nvme/smartctl exporter; add DCGM exporter if the PC has an NVIDIA GPU.
3. Initial Grafana dashboard: all the above metrics on a unified timeline.

**Acceptance Criteria**

- M0 section in `ci_report.sh` passes: all service health-check endpoints are reachable; `ENVIRONMENT.md` contains no `TBD` placeholders.
- Manual spot-check: node metrics in Grafana show live data.

---

## M1 bpftrace Tutorial + Exercise Set

**Deliverables**

1. `docs/M1-tutorial.md`: targeting readers who understand operating systems but have zero eBPF background. Covers: eBPF program model (event sources, maps, verifier — one-sentence-level explanations), bpftrace syntax essentials, probe types (kprobe/uprobe/tracepoint/USDT), aggregations and primitives (count/hist/arg access).
2. `exercises/`: at least 8 exercises, each containing `trigger.sh` (produces the behavior to be observed), `expected.md` (reference answer), `verify.sh` (automated comparison). Exercise answers must be knowable in advance. Coverage: syscall counting, file-open tracing, block IO latency, scheduling latency, short-lived process capture, user-space uprobe.

**Acceptance Criteria**

- `ci_report.sh` M1 section: automatically runs all `verify.sh` scripts, output matches the answer key.
- Manual step: user completes the exercises following the tutorial.

---

## M2 Custom Tool: Block IO Latency Histogram

**M2.0 Toolchain and Engineering Standards Setup (prerequisite subtask)**

1. `rust-toolchain.toml` at repository root: pinned stable toolchain channel, with components `rustfmt` and `clippy`. Additional components per the library selected in D-001:
   - aya: target `bpfel-unknown-none` and `bpf-linker` (installed via cargo);
   - libbpf-rs: `libbpf-cargo` for BPF skeleton generation.
2. Finalize D-001 in `DECISIONS.md`: fill in the date and record the libbpf-rs vs. aya selection with rationale, validated against the M0 probe results in `ENVIRONMENT.md` (kernel version, BTF, `CONFIG_BPF*`).
3. `docs/M2-coding-standards.md`: engineering standards for all custom tools in this project, covering:
   - formatting: `cargo fmt` (default rustfmt style; any project-level deviations recorded in `rustfmt.toml`);
   - linting: `cargo clippy -- -D warnings` (warnings treated as errors; any allowed lints listed explicitly with justification);
   - build/test routine: `cargo build --release`, `cargo test` where unit-testable logic exists;
   - error handling and logging conventions for tool code;
   - reproducibility requirements per AGENTS.md (fixed parameters in scripts, ≥3 runs per configuration).
4. `ci_report.sh` M2 section extended to run `cargo fmt --check` and `cargo clippy -- -D warnings` on all tool crates, failing the milestone on any violation.

**Deliverables**

1. `tools/biolat/`: Rust eBPF tool that collects latency statistics for block IO completion events and outputs a log2 histogram (equivalent to bcc `biolatency`).
2. `docs/M2-biolat-design.md`: design note (including technology selection entry point and a "how to manually verify" checklist).
3. `scripts/verify_m2.sh`: fixed-parameter fio workload (≥5 runs), runs this tool and bcc `biolatency` in parallel, automated comparison.

**Acceptance Criteria (Oracle: bcc biolatency)**

- Under the same fio workload, the median and P99 latencies reported by this tool and bcc `biolatency` are within the same order of magnitude (deviation < 2×); histogram shapes are qualitatively consistent (peak position is the same).
- If bcc is unavailable on the target kernel, a proposal must be submitted describing an alternative oracle (e.g., using iostat's await for order-of-magnitude validation); self-initiated replacement is forbidden.

---

## M3 Custom Tool: Run Queue Latency + Off-CPU Attribution

**Deliverables**

1. `tools/runqlat/`: equivalent to bcc `runqlat` (histogram of queuing delay from thread ready to actually running on CPU).
2. `tools/offcpu/`: equivalent to bcc `offcputime` (blocking time aggregated by stack).
3. `scripts/verify_m3.sh`: automated verification of three known injection scenarios—
   - Scenario A: CPU saturation (oversubscribed CPU-intensive threads) → runqlat must show significantly elevated queuing;
   - Scenario B: lock contention micro-benchmark → offcpu must attribute to the corresponding futex/lock stack;
   - Scenario C: synchronous disk wait → offcpu must attribute to the IO wait stack.
4. Corresponding design note.

**Acceptance Criteria**

- Compared with bcc `runqlat` / `offcputime` under the same workload, magnitudes are consistent (deviation < 2×).
- All three injection scenarios are attributed to the pre-labeled cause; incorrect attribution means failure.

---

## M4 Comprehensive Case Study

**Deliverables**

1. `docs/M4-case-study.md`: a complete attribution report on a user-specified real lab workload (candidates: sqlite insert benchmark, fio queue-depth sweep, local inference service CPU-side). Structure: anomaly observed at the monitoring layer → hypothesis list → eBPF evidence → conclusion.
2. Each conclusion in the report is accompanied by a re-runnable script.

**Acceptance Criteria**

- Contains at least one finding that "first-layer monitoring (G1 metrics) cannot explain and must be attributed by eBPF tools"; if no natural anomaly occurs during the experiment, injecting a known anomaly and documenting that fact is permitted.
- The user can randomly spot-check any two scripts to reproduce the corresponding conclusions.
- `ci_report.sh` performs a smoke regression across all milestones and passes overall.

---

## Changes

This file may only be modified by the user. When the agent believes adjustments are needed, it submits a proposal to `proposals/`.
