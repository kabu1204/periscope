# DECISIONS.md — Decision Log (Append-Only, Modifying Historical Entries Is Forbidden)

> Append one entry per technology selection. Record rationale and alternatives considered, for post-hoc audit.

## Format

```
## D-NNN Title
- Date:
- Decision:
- Rationale:
- Alternatives considered (and reasons for not adopting):
- Basis: (ENVIRONMENT.md entry / benchmark data / proposal number)
```

## Entries

## D-001 eBPF Development Language and Library
- Date: 2026-08-09
- Decision: Rust with libbpf-rs (libbpf-cargo for skeleton generation)
- Rationale: BTF is available on the target kernel (`CONFIG_DEBUG_INFO_BTF=y`), enabling CO-RE (Compile Once – Run Everywhere). libbpf-rs uses the kernel's libbpf library for skeleton-based loading — the same mechanism used by bcc/libbpf-tools, making oracle comparison fair. BPF programs are written in C (compiled with clang), which is the standard and well-documented approach. libbpf-cargo integrates BPF compilation into the Cargo build system via `build.rs`.
- Alternatives considered:
  - aya: requires `bpfel-unknown-none` target and `bpf-linker` (not available as Debian packages, require rustup). aya writes BPF programs in Rust, which is newer and less documented. aya's Debian package (0.13.1) is older than the current crates.io release.
  - bcc-python: bpftrace substitutes during the tutorial phase (M1); not suitable for custom standalone tools.
  - C + libbpf: lower development efficiency than Rust for userspace code.
- Basis: ENVIRONMENT.md PC probe results (kernel 6.12.95, BTF available, `CONFIG_BPF*` enabled); AGENTS.md engineering constraints.

## D-002 Container Runtime: podman
- Date: 2026-08-09
- Decision: Use podman (5.4.2) + podman-compose (1.3.0) as the container runtime for the monitoring stack, instead of Docker.
- Rationale: User preference for a lightweight, daemonless container runtime. podman is compatible with docker-compose YAML files and is available in Debian 13 repositories. Avoids running a persistent daemon (dockerd) on the research machine.
- Alternatives considered: Docker (docker.io 26.1.5 — was partially installed but removed per user request); nerdctl (not available in Debian 13 repos).
- Basis: ENVIRONMENT.md PC probe results; user instruction.

## D-003 eBPF → Prometheus Exporter Design
- Date: 2026-08-10
- Decision: Give each custom eBPF tool (biolat, runqlat, offcpu) an opt-in long-lived exporter mode (`--exporter ADDR`) that serves a Prometheus text-format `/metrics` endpoint via a hand-rolled HTTP responder (`tools/common`, crate `periscope-exporter`). Prometheus scrapes the three exporters on a dedicated port block (biolat 9601, runqlat 9602, offcpu 9603; node_exporter uses 9100). Metrics: `periscope_block_io_latency_seconds` and `periscope_runqueue_latency_seconds` as histograms (log2 us buckets as cumulative `le` buckets in seconds, plus `_sum`/`_count` from a new `hist_sum` BPF map); `periscope_offcpu_seconds_total{pid,comm,kernel_stack_id,user_stack_id}` as counters bounded to the top 50 stacks.
- Rationale: The user expects eBPF data to be visualizable in Grafana continuously, not only via one-shot stdout traces. A minimal in-tool exporter avoids new dependencies (per M2 coding standards) and reuses the existing containerized Prometheus/Grafana stack. Hand-rolled HTTP is sufficient for a 15s scrape interval.
- Alternatives considered:
  - prometheus + tiny_http crates: more idiomatic but adds transitive dependencies and a runtime; rejected to keep zero new dependencies.
  - node_exporter textfile collector via cron: lossy (no histogram `_sum`), higher latency, requires cron + parsing.
  - Existing general-purpose eBPF exporters (Cloudflare, Cilium): heavier, drifts toward NG3 platform territory.
- Basis: proposals/P-001-ebpf-prometheus-exporter.md (approved 2026-08-10); user decision on HTTP library, scope, and process model.
