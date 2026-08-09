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
