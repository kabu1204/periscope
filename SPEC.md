# SPEC.md — Project Scope (Frozen, User-Only Modifications)

## Background

The user conducts system experiments (SSD IO, database, inference service) on a personal research environment for better understanding into the system behavior and optimization. Currently lacking: continuous visibility into system-layer state during experiments, and the ability to attribute performance anomalies.

## Goals

- **G1**: Deploy centralized time-series monitoring so that system metrics (CPU, memory, disk IO, network, GPU if available) within any experimental time window can be viewed aligned on a unified timeline.
- **G2**: Build a custom eBPF toolset covering two categories of attribution: latency distributions (block IO, run queue) and blocking attribution (off-CPU stack sampling).
- **G3**: Through one complete case study, establish a reusable workflow of "anomaly discovery → coarse localization → eBPF attribution → conclusion and reproduction."

## Non-goals

- **NG1**: No GPU kernel-level profiling (nsys/CUPTI ecosystem; out of scope).
- **NG2**: No deployment of any components on shared cluster machines (no root access; cluster observability uses only in-application instrumentation and is out of scope).
- **NG3**: No Kubernetes or heavy-weight observability platforms (Pixie, Deepflow, etc.).
- **NG4**: No alerting system.
- **NG5**: No eBPF applications in container orchestration or security auditing (e.g., Tetragon-class tools).

Any idea touching the above boundaries must be submitted as a proposal first; direct implementation is forbidden.

## Environment Constraints

- Target machines: PC (Linux, specific kernel version per `ENVIRONMENT.md` probe results), TrueNAS SCALE.
- All technology choices are validated against the probe results in `ENVIRONMENT.md` (kernel version, BTF, `CONFIG_BPF*` options).
- Deployment form: containerized (docker compose), configuration checked into the repository.

## Acceptance Philosophy

Acceptance of all custom tools in this project does not rely on code review but on **oracle comparison**: comparing output with the corresponding bcc tool under the same workload, or verifying attribution correctness in injection scenarios with known answers. The specific oracle and tolerance definitions for each milestone are in `ROADMAP.md`.
