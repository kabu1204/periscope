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
./periscope trace all -d 10       # all three tools at once
./periscope trace offcpu -d 10 --top 5
```

**Continuous eBPF metrics in Grafana** (exporters feeding the eBPF dashboard):

```bash
./periscope export start          # start biolat/runqlat/offcpu exporters (:9601-9603)
./periscope export stop
# then open Grafana -> "Periscope eBPF Attribution"
```

See `./periscope --help` and `./periscope tools` for the full surface.

### Adjusting the eBPF reporting frequency

The eBPF tools record every event in real time; the reporting frequency is how
often Prometheus pulls the accumulated state. The three eBPF jobs scrape at **3s**
by default (finer than the 15s global default used for node_exporter).

To change it, edit `monitoring/prometheus/prometheus.yml` and set `scrape_interval`
on the `biolat` / `runqlat` / `offcpu` jobs:

```yaml
  - job_name: "biolat"
    scrape_interval: 1s        # raise frequency (or 5s/10s to lower it)
    static_configs:
      - targets: ["localhost:9601"]
```

Then reload Prometheus (no container restart needed):

```bash
curl -X POST http://localhost:9090/-/reload
```

Notes:
- Also set the **Periscope eBPF Attribution** dashboard's `refresh` to match
  (currently `3s`) so the panels actually redraw at the finer interval.
- Lower intervals are most useful under heavy IO/scheduling load. For
  `histogram_quantile` percentiles, use a rate window a few times the scrape
  interval (e.g. `[30s]` or `[1m]`) to avoid noisy percentiles when traffic is
  light.
