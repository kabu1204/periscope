# Proposal Template

> When the agent believes it needs to deviate from SPEC.md / ROADMAP.md, or the current approach is infeasible, copy this template to create `proposals/P-NNN-Title.md`, submit it, then stop related work and wait for user approval.

## P-001 eBPF → Prometheus Exporter Mode

- Date: 2026-08-10
- Submitted by: Agent (post-M4 session)
- Related milestone: New capability beyond M0–M4 (all complete)

## Background

The user expected periscope to generate data/traces that Grafana can visualize
continuously. Today the two halves of the project do not exchange data:

- The monitoring stack (Prometheus + Grafana + node_exporter) collects only
  system-level metrics (CPU, memory, disk IO rates). It runs continuously.
- The custom eBPF tools (biolat, runqlat, offcpu) print histograms and stack
  reports to stdout. They are run by hand, for a bounded window, and emit nothing
  to Prometheus or Grafana.

Evidence: the eBPF tools have no exporter, metrics endpoint, or any bridge to the
monitoring stack; `monitoring/prometheus/prometheus.yml` scrapes only Prometheus
and node_exporter. The M4 case study demonstrates the intended manual pattern
(Grafana detects/localizes in time → the eBPF tool is run by hand to attribute).

The user would like the eBPF tools' data to be visualizable in Grafana, i.e. the
"eBPF exporter" model: run the tools long-lived, expose `/metrics`, let Prometheus
scrape, graph latency histograms and off-CPU time over time.

## Proposed Change

Add an optional **exporter mode** to each of the three eBPF tools, plus monitoring
wiring. This does not modify SPEC.md or ROADMAP.md text; it adds capability beyond
the (now complete) M0–M4 milestones.

1. Each tool gains a flag (e.g. `--exporter :PORT`) that runs a long-lived process
   serving a Prometheus text-format `/metrics` endpoint until killed:
   - **biolat** → histogram `periscope_block_io_latency_seconds` (log2 buckets as
     cumulative `le` buckets, plus `_sum` and `_count`). Requires adding a
     total-latency sum counter to the BPF program.
   - **runqlat** → histogram `periscope_runqueue_latency_seconds`, same treatment.
   - **offcpu** → counter `periscope_offcpu_seconds_total{pid,comm,stack_id}` with
     bounded label cardinality (stack ids, not symbolized names; optional `--top N`).
2. The HTTP endpoint is a minimal hand-rolled responder (no new crates): serve
   `GET /metrics` with the current map contents, 404 otherwise.
3. `monitoring/prometheus/prometheus.yml`: add scrape jobs for the three exporters
   (dedicated port block, e.g. 9601/9602/9603; node_exporter uses 9100).
4. `monitoring/grafana/dashboards/`: add an eBPF attribution dashboard (block IO and
   run-queue latency percentiles via `histogram_quantile`, top off-CPU stacks).
5. `scripts/verify_exporter.sh`: assert `/metrics` returns 200 with expected series,
   Prometheus reports `up{job=...}==1`, and values move under a known workload.
6. `ci_report.sh`: add an exporter section running the verification, keeping the
   existing per-tool fmt/clippy/build checks.
7. Docs: `docs/M5-exporter-design.md` (architecture, metric reference, how to run,
   manual-verify checklist); update `STATE.md`; append a DECISIONS.md entry (port
   block, metric naming, exporter design).

Existing one-shot CLI behavior of each tool is unchanged; exporter mode is opt-in.

## Impact Analysis

- **Impact on schedule**: M0–M4 are complete; this is new, self-contained work
  (roughly M5-sized: ~1–2 days). No change to existing milestone acceptance.
- **Impact on other milestones**: none — the M0–M4 tools, scripts, and `ci_report.sh`
  checks remain as-is; exporter mode is additive. Full regression (`ci_report.sh
  m0..m4`) must still pass.
- **Does this touch any non-goals**: adjacent to **NG3** (no heavyweight
  observability platforms). Rationale: this is not a platform — it adds a Prometheus
  *exporter* to the existing tools, consistent with the containerized
  Prometheus/Grafana stack already deployed in M0. No Pixie/Deepflow/Kubernetes is
  introduced. Exporters run on the host with the same privileges the tools already
  require (root/CAP_BPF, BTF access), not in containers.

## Alternatives

- **Keep tools stdout-only** (status quo): does not meet the user's expectation of
  Grafana-visualizable, continuous eBPF data.
- **Run tools on a cron and push textfiles to node_exporter's textfile collector**:
  possible without code changes to HTTP, but lossy (no histogram `_sum`, awkward
  per-stack labels) and still requires cron + parsing; an in-tool exporter is cleaner
  and lower-latency.
- **Adopt an existing eBPF exporter (e.g. Cloudflare's, Cilium)**: heavier, general-
  purpose, and drifts toward the NG3 platform territory the SPEC excludes; building a
  minimal exporter on the existing tools keeps the custom-tool, learning-focused
  character of the project.

## User Decision

- [x] Approved
- [ ] Rejected
- Comments: Approved 2026-08-10.
