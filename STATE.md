# STATE.md — Project Status (Agent Must Read/Write Every Session)

> This file is maintained by the agent. Read at the start of each session, update at the end. Fixed format as follows.

## Current Position

- Current milestone: **M5 (eBPF exporter mode) complete — awaiting user confirmation**
- Status: M0–M4 complete (final ROADMAP milestone M4 done). M5 exporter capability added under approved proposal P-001. `ci_report.sh all` passes 27/27.

## Previous Session Summary

M3 was committed, then M4 (comprehensive case study) was completed in this session.

**M4 deliverables**:

1. **`docs/M4-case-study.md`**: full attribution report on a sqlite insert benchmark — monitoring-layer anomaly → hypothesis list → eBPF evidence → conclusion.

2. **`scripts/m4/`** workloads and attribution scripts:
   - `sqlite_bench.c`: one transaction per row (`journal_mode=DELETE`, `synchronous=FULL`), so each commit fsyncs; throughput is governed by block IO latency.
   - `run_baseline.sh` (~345 rows/sec), `run_anomaly.sh` (background fio writer → ~166 rows/sec).
   - `attribution_offcpu.sh`: asserts offcpu attributes `sqlite_bench` to `fdatasync → ext4_sync_file → folio_wait_writeback → io_schedule`.
   - `attribution_biolat.sh`: asserts biolat's anomaly median exceeds baseline (peak shifted 256–511us → 512–1023us).

3. **`scripts/verify_m4.sh`**: smoke regression over all four conclusions (throughput drop, fsync attribution, latency rise, no CPU saturation). 4/4 pass.

**Key finding**: node_exporter (disk util, write rate, load) showed disk activity but could not attribute the slowdown; eBPF (biolat + offcpu) identified doubled block IO latency on the fsync commit path. The anomaly was injected (permitted by ROADMAP M4).

**Also**: increased verify_m2.sh fio workload (32M→64M, iodepth 8→16) after a transient M2 oracle failure in the full regression — the workload occasionally finished too fast for a reliable histogram.

## Next Steps

1. **User confirmation**: Review M5 (exporter mode) deliverables. M0–M4 (the ROADMAP) are complete.
2. **Exporters are host processes**: start them manually (`biolat --exporter :9601` etc.); consider systemd units if they should run continuously.
3. **TrueNAS**: when accessible, re-probe and add to monitoring stack.

## Open Questions

- TrueNAS SCALE machine accessibility (not reachable since M0).
- offcpu user-stack symbolization (addresses printed raw; kernel stacks symbolized).
- Grafana admin password was changed in the UI (no longer `admin`); dashboard file-provisioning is unaffected, but note the CI cannot log in as admin.

## Recent Update

- Date: 2026-08-10
- Updated by: Agent (M5 session)

## M5 Session Summary (appended 2026-08-10)

**M5 — eBPF → Prometheus exporter mode** (proposal `proposals/P-001-ebpf-prometheus-exporter.md`, approved):

1. **`tools/common`** (crate `periscope-exporter`): hand-rolled minimal HTTP responder serving `GET /metrics` in Prometheus text format; no external crates.
2. **Exporter mode on all three tools** (`--exporter ADDR`): biolat (9601), runqlat (9602), offcpu (9603). Histogram tools gained a `hist_sum` BPF map for `_sum`/`_count`; metrics are `periscope_block_io_latency_seconds` and `periscope_runqueue_latency_seconds` (histograms) and `periscope_offcpu_seconds_total{pid,comm,kernel_stack_id,user_stack_id}` (counters, top 50 stacks).
3. **Monitoring wiring**: three scrape jobs in `monitoring/prometheus/prometheus.yml`; new dashboard `monitoring/grafana/dashboards/ebpf-attribution.json`.
4. **Verification**: `scripts/verify_exporter.sh` (7 checks: /metrics content, count growth, Prometheus `up==1` per job); `ci_report.sh` M5 section. `ci_report.sh all` passes 27/27.
5. **Docs/decisions**: `docs/M5-exporter-design.md`; DECISIONS.md D-003 (exporter design, port block, metric naming).
