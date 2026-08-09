# ebpf-lab

Observability and performance engineering capability project for a personal lab environment (PC + TrueNAS SCALE).

## Repository Conventions

| File | Purpose | Who May Modify |
|------|---------|----------------|
| `AGENTS.md` | Agent behavior rules: workflow, permissions, style, engineering constraints | User |
| `SPEC.md` | Project scope and non-goals (frozen) | User |
| `ROADMAP.md` | Milestones and acceptance criteria | User |
| `STATE.md` | Current status (must read/write every session) | Agent |
| `ENVIRONMENT.md` | Environment probe results, basis for technology choices | Agent (M0 only) |
| `DECISIONS.md` | Decision log (append-only) | Agent |
| `proposals/` | Scope change proposals | Agent submits, user approves |
| `checkpoints/` | One-page report per milestone | Agent |
| `docs/` | Design notes | Agent |
| `ci_report.sh` | One-shot project status verification | Agent appends per milestone |

## Quick Start (First Instruction to the Agent)

> Read AGENTS.md, then follow the mandatory workflow to begin M0.

## Daily Use

- Check actual project status: `./ci_report.sh all`
- Review progress: read the latest one-page report in `checkpoints/`
- Decisions: intervene only when a new proposal appears in `proposals/`

## Using periscope

The `./periscope` CLI is the unified entry point for the two core workflows.

**Continuous system monitoring** (Prometheus + Grafana + node_exporter):

```bash
./periscope stack up        # start the monitoring stack
./periscope stack status    # show running containers
./periscope stack down      # stop it
```

**Run an experiment and collect data** (workload + monitoring + eBPF evidence):

```bash
./periscope run sqlite-baseline   # or sqlite-anomaly
# writes ./results/<experiment>-<timestamp>/{benchmark,biolat,offcpu,monitoring}.txt
```

**Ad-hoc attribution** (run an eBPF tool directly):

```bash
./periscope trace biolat -d 10    # one-shot histogram
./periscope trace runqlat -d 10
./periscope trace offcpu -d 10 --top 5
```

**Continuous eBPF metrics in Grafana** (exporters feeding the eBPF dashboard):

```bash
./periscope export start          # start biolat/runqlat/offcpu exporters (:9601-9603)
./periscope export stop
# then open Grafana -> "Periscope eBPF Attribution"
```

See `./periscope --help` and `./periscope tools` for the full surface.
