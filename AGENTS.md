# AGENTS.md — ebpf-lab

## Project Overview

Build observability and performance engineering capabilities on a personal research environment. Ultimate goal: achieve eBPF-based performance attribution for lab workloads (SSD IO, database, inference service CPU-side), and maintain a centralized time-series monitoring stack.

The project owner (hereafter "the user") has a systems and compiler background but is new to eBPF / observability. All documents serve the dual purpose of engineering documentation and tutorial material.

## Mandatory Per-Session Workflow

1. **Start**: Read `SPEC.md`, `ROADMAP.md`, `STATE.md`, `ENVIRONMENT.md`, `DECISIONS.md` in that order.
2. **Work**: Only execute tasks within the current milestone as marked in `STATE.md`.
3. **End**: Update `STATE.md` (what was completed, next steps, open questions); if a technology choice was made, append to `DECISIONS.md`.

## Permission Boundaries

- **Read-only**: `SPEC.md`, `ROADMAP.md`. Any modification request must be submitted as a proposal in `proposals/` (format: see `proposals/TEMPLATE.md`), awaiting user approval. Self-initiated scope changes are forbidden.
- `ENVIRONMENT.md` may only be updated during M0 or when the user explicitly requests it.
- Installing kernel modules is forbidden; modifying host system configuration is forbidden; the monitoring stack must be deployed entirely in containers.
- When the current approach is found to be infeasible (e.g., kernel version limitations), stop and submit a proposal. Self-initiated switching to an alternative approach is forbidden.

## User Communication and Documentation Style

Apply the following guidelines to user-facing communication, task summaries, and documentation:

- Use a formal, precise, and professional tone.
- Present explanations clearly.
- Organize content so that it is easy to read and follow.
- Avoid ambiguous or undefined terms, unnecessary jargon, slang, and colloquial expressions such as "head-of-line", "arms", "regime", "verdict", and "caveat".

## Engineering Constraints

- eBPF tool development language: Rust (libbpf-rs or aya; the selection result and rationale must be recorded in `DECISIONS.md`).
- bpftrace is permitted during the tutorial and quick-validation phases.
- All benchmarks must be reproducible: parameters are fixed in scripts, each configuration is run at least 3 times, and distributions (not single values) are reported.
- Only synthetic workloads are used (fio, sqlite benchmark, self-written micro-benchmarks); benchmarking against real data directories is forbidden.
- Validation principle: every tool must have an oracle (typically the corresponding bcc tool or an injection scenario with a known answer); acceptance criteria are defined in `ROADMAP.md`.
- Conventional commit messages are used for all commits.

## Milestone Definition of Done (DoD)

A milestone is complete only when all of the following conditions are met:

1. `ci_report.sh` passes all checks (the milestone's verification has been incorporated into the script).
2. A new design note is added under `docs/`: what was done, why it was done that way, principles explained, and a "how to manually verify" checklist.
3. `checkpoints/MX.md` one-page checkpoint report: deliverables list, verification evidence (commands + output summary), deviations from ROADMAP, and suggested next steps.

After completing the DoD, stop and wait for user confirmation before proceeding to the next milestone.
