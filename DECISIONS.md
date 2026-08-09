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

## D-001 eBPF Development Language
- Date: (To be filled before M2)
- Decision: Rust (libbpf-rs or aya, specific library to be selected)
- Rationale: Project constraint (see AGENTS.md)
- Alternatives considered: bcc-python (bpftrace can substitute during tutorial phase); C + libbpf (lower development efficiency)
- Basis: AGENTS.md engineering constraints

## D-002 Container Runtime: podman
- Date: 2026-08-09
- Decision: Use podman (5.4.2) + podman-compose (1.3.0) as the container runtime for the monitoring stack, instead of Docker.
- Rationale: User preference for a lightweight, daemonless container runtime. podman is compatible with docker-compose YAML files and is available in Debian 13 repositories. Avoids running a persistent daemon (dockerd) on the research machine.
- Alternatives considered: Docker (docker.io 26.1.5 — was partially installed but removed per user request); nerdctl (not available in Debian 13 repos).
- Basis: ENVIRONMENT.md PC probe results; user instruction.
