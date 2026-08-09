# Design Note: M5 — eBPF → Prometheus Exporter Mode

## Conclusion First

The three custom eBPF tools (biolat, runqlat, offcpu) now have an optional
**exporter mode**: a long-lived process that serves a Prometheus `/metrics`
endpoint. Prometheus scrapes these endpoints and Grafana graphs the results,
closing the gap identified by the user — previously the eBPF tools only printed to
stdout and never fed the monitoring stack. The feature was approved as proposal
`proposals/P-001-ebpf-prometheus-exporter.md`.

## Background and Principles

### The two observation layers

The project has two complementary layers (see SPEC.md G1/G2):

- **Continuous time-series monitoring** (Prometheus + node_exporter + Grafana):
  records system metrics over time, low overhead, always on. Answers *"when did
  something change, and on which resource?"*
- **On-demand eBPF attribution** (biolat, runqlat, offcpu): answers *"why"* by
  measuring kernel-level latency and blocking. Historically these were CLI tools
  run by hand for a bounded window.

Exporter mode connects the two: the eBPF tools become long-lived **exporters** —
processes that keep their BPF programs attached and expose the accumulated maps as
Prometheus metrics. Prometheus scrapes them on its normal interval, and the data
becomes a time series that Grafana renders. This is the standard "eBPF exporter"
pattern (as used by Cilium, Cloudflare's eBPF exporter, etc.), implemented minimally
on top of the existing tools.

### Prometheus data model constraints

Prometheus understands a small set of metric types. Two matter here:

- **Histogram**: a set of cumulative buckets with `le` ("less than or equal")
  labels, plus `_sum` and `_count`. Prometheus computes percentiles server-side with
  `histogram_quantile()`. Our tools' log2 microsecond buckets map directly: bucket
  index N (covering 2^(N-1)..2^N-1 us) becomes `le = 2^N us`, expressed in seconds.
  Because Prometheus buckets must be cumulative, the exporter emits running totals.
  `_sum` (total observed latency) is required for meaningful percentiles and
  averages; it is accumulated in a small BPF array map added to each histogram tool.
- **Counter**: a monotonically increasing value. offcpu's per-stack blocked time is
  a natural counter; `rate()` then gives "seconds blocked per second" per stack.

Label **cardinality** (the number of distinct label sets) is the main cost driver in
Prometheus. offcpu aggregates by (pid, comm, kernel stack id, user stack id), which
can be large; the exporter bounds it by exporting only the top stacks by total time
and by using numeric stack *ids* rather than full symbolized stacks as labels.

## Design

### Exporter mode behavior

Each tool keeps its existing one-shot CLI behavior. A new `--exporter ADDR` flag
switches to exporter mode:

- Load and attach the BPF programs once (as today).
- Bind a minimal HTTP listener on `ADDR`.
- On each `GET /metrics`, read the current BPF maps, render the Prometheus text
  format, and return it. The map read happens at scrape time; no background thread
  is needed.
- Run until killed (SIGINT/SIGTERM); detach and exit cleanly.

### The HTTP responder (`tools/common`)

A tiny shared crate, `periscope_exporter`, provides `serve(addr, render)`. It is a
blocking, sequential `TcpListener` loop: read the request line, serve `GET /metrics`
(and `/`) with `render()`'s body and `Content-Type: text/plain; version=0.0.4`,
return 404 otherwise. Per the M2 coding standards and P-001, it uses **no external
crates** — a sequential responder is sufficient because Prometheus scrapes every 15s.

### Metric reference

| Tool | Metric | Type | Labels |
|------|--------|------|--------|
| biolat | `periscope_block_io_latency_seconds` | histogram | `le` |
| runqlat | `periscope_runqueue_latency_seconds` | histogram | `le` |
| offcpu | `periscope_offcpu_seconds_total` | counter | `pid`, `comm`, `kernel_stack_id`, `user_stack_id` |

Histograms expose `_bucket{le=...}`, `_sum`, and `_count`. offcpu exports at most
the top 50 stacks by total blocked time to bound cardinality.

### BPF change

Each histogram tool's BPF program gains a two-slot array map `hist_sum`: slot 0
accumulates total latency in microseconds (for `_sum`), slot 1 the event count
(for `_count`). offcpu needed no BPF change — its `counts` map already accumulates
per-key microseconds.

### Prometheus / Grafana wiring

- `monitoring/prometheus/prometheus.yml`: three new scrape jobs — `biolat`
  (localhost:9601), `runqlat` (9602), `offcpu` (9603). node_exporter uses 9100, so
  the 960x block is distinct and documented in the file.
- `monitoring/grafana/dashboards/ebpf-attribution.json`: panels for block IO and
  run-queue latency P50/P99 (`histogram_quantile` over the `_bucket` series), block
  IO op rate (`rate(..._count)`), and top off-CPU stacks (`topk` over
  `rate(periscope_offcpu_seconds_total)`).

## Verification

`scripts/verify_exporter.sh` starts all three exporters, drives known workloads
(reusing the M3/M4 triggers), and asserts:

1. `/metrics` returns the expected metric families (block IO histogram, run queue
   histogram, off-CPU series).
2. The block IO `_count` increases under the sqlite workload.
3. Prometheus reports `up{job="<tool>"} == 1` for each exporter.

Representative output:

```
=== biolat exporter ===
  PASS: biolat /metrics exposes block IO histogram
  PASS: biolat _count increased under workload (15563 -> 19221)
=== runqlat exporter ===
  PASS: runqlat /metrics exposes run queue histogram
=== offcpu exporter ===
  PASS: offcpu /metrics exposes off-CPU series
=== Prometheus scrape targets ===
  PASS: Prometheus scrapes biolat (up==1)
  PASS: Prometheus scrapes runqlat (up==1)
  PASS: Prometheus scrapes offcpu (up==1)
```

## How to Manually Verify

1. Build the tools:
   ```bash
   for t in biolat runqlat offcpu; do (cd tools/$t && cargo build --release); done
   ```
2. Start the exporters (each blocks; run in separate terminals or background):
   ```bash
   ./tools/biolat/target/release/biolat --exporter :9601 &
   ./tools/runqlat/target/release/runqlat --exporter :9602 &
   ./tools/offcpu/target/release/offcpu --exporter :9603 &
   ```
3. Check a metrics endpoint directly:
   ```bash
   curl -s localhost:9601/metrics | grep periscope_block_io_latency_seconds
   # expect _bucket{le=...}, _sum, _count lines
   ```
4. Drive a workload (e.g. the M4 sqlite benchmark) and re-check that `_count` grows.
5. Confirm Prometheus scrapes them: http://localhost:9090/targets should show the
   biolat/runqlat/offcpu jobs `up` once the exporters are running.
6. Open the Grafana dashboard **Periscope eBPF Attribution** and confirm the panels
   graph latency percentiles and top off-CPU stacks.
7. Run the automated check:
   ```bash
   ./scripts/verify_exporter.sh   # expect pass=7 fail=0
   ```

## Known Limitations

- **Exporters run on the host**, not in containers: they need root/CAP_BPF and host
  BTF access, exactly like the one-shot tools. They must be started manually (or via
  a systemd unit, not yet provided); Prometheus shows the jobs as `down` when they
  are not running.
- **offcpu label cardinality** is bounded to the top 50 stacks by total time and
  uses stack ids, not symbolized names; resolving a stack id to symbols still
  requires running the one-shot tool.
- **Sequential HTTP responder**: one connection at a time. Sufficient for a 15s
  scrape interval; not a general-purpose web server.
- **No persistence in the tools**: metrics are whatever is in the BPF maps at scrape
  time. Restarting an exporter resets its histograms/counters (Prometheus treats
  counter resets normally for `rate()`).
