# M4 Case Study: Attributing a sqlite Insert Slowdown

## Conclusion First

A sqlite insert benchmark slowed from ~345 rows/sec to ~180 rows/sec when a background writer was injected. The monitoring layer (node_exporter: disk utilization, write rate, load average) showed disk activity but could not explain why the benchmark was slow. eBPF attribution identified the cause: block IO completion latency roughly doubled (biolat peak shifted from the 256–511us bucket to 512–1023us, with a tail out to 262ms), and the benchmark's off-CPU time is dominated by the synchronous commit path (`fdatasync → ext4_sync_file → folio_wait_writeback → io_schedule`). The conclusion is that the benchmark is fsync-bound and the injected background writer inflated block IO latency, directly slowing each commit. Every step is re-runnable via the scripts in `scripts/m4/` and `scripts/verify_m4.sh`.

## The Workload

`scripts/m4/sqlite_bench.c` inserts rows one transaction at a time with `journal_mode=DELETE` and `synchronous=FULL`. Each `COMMIT` forces a journal write plus `fdatasync`, so the benchmark's throughput is governed by block IO completion latency. The database lives on `/var/tmp` (ext4 on `vda`), a block-backed filesystem — `/tmp` is tmpfs and would bypass the block layer entirely.

Baseline (no anomaly), 3 runs:

```
rows=3000 elapsed=9.025s rows_per_sec=332
rows=3000 elapsed=8.790s rows_per_sec=341
rows=3000 elapsed=8.685s rows_per_sec=345
```

## Step 1 — Anomaly observed at the monitoring layer

node_exporter metrics (scraped by Prometheus, queried via its HTTP API) around a run:

| Metric | Idle | During benchmark |
|--------|------|------------------|
| `rate(node_disk_io_time_seconds_total{device="vda"}[1m])` | ~0.58 | ~0.40 |
| `rate(node_disk_writes_completed_total{device="vda"}[1m])` | — | ~950 writes/s |
| `node_load1` | ~1.5 | ~1.4 |

The monitoring layer tells us the disk is doing ~950 writes/s and is moderately busy, and that one CPU is occupied. It does **not** tell us why inserts are slow, nor what changed when throughput later dropped.

## Step 2 — Hypothesis list

Candidate causes for slow inserts:
1. CPU saturation — the benchmark or another process is waiting for CPU.
2. Lock contention — threads blocking on a mutex/futex.
3. Block IO latency — each commit's fsync waits on slow storage.

The monitoring layer cannot distinguish these; all three would show "some disk activity, some load."

## Step 3 — eBPF evidence

### runqlat rules out CPU saturation

Under the benchmark, `runqlat` shows the run queue latency tail (>=64us) fraction stays at baseline levels — tasks are not queuing for CPU. This rules out hypothesis 1.

### offcpu attributes the blocked time to the fsync path

`offcpu` on the benchmark process (`sqlite_bench`) shows the dominant off-CPU kernel stack:

```
__x64_sys_fdatasync
ext4_sync_file
do_fsync
file_write_and_wait_range
__filemap_fdatawait_range
folio_wait_bit_common
folio_wait_writeback
io_schedule
```

This is the synchronous commit path: `fdatasync` flushes the journal and data, then waits on writeback completion in `io_schedule`. This rules out hypothesis 2 (no futex/lock stack dominates) and points at block IO.

### biolat shows the latency shift under the anomaly

biolat during a **baseline** run (block IO completion latency, peak in the 256–511us bucket):

```
     usecs               : count     distribution
      256 -> 511        : 10894    |########################################|
      512 -> 1023       : 4108     |###############                         |
     1024 -> 2047       : 217      |
```

biolat during the **anomaly** run (a background `fio` job issues high queue-depth random writes to `vda`):

```
     usecs               : count     distribution
      256 -> 511        : 28196    |######
      512 -> 1023       : 166941   |########################################|
     1024 -> 2047       : 101930   |########################
     2048 -> 4095       : 13367    |###
      ...
   131072 -> 262143     : 3        |
```

The peak shifted from 256–511us to 512–1023us and a long tail appeared (out to ~262ms). Median block IO latency roughly doubled.

Throughput over the same runs:

| Run | rows/sec |
|-----|----------|
| Baseline | ~345 |
| Anomaly | ~180 |

## Step 4 — Conclusion

The benchmark is fsync-bound: each commit blocks in the `fdatasync → ext4_sync_file → io_schedule` path waiting for block IO completion. The injected background writer inflated block IO completion latency (biolat peak doubled, long tail), which directly slowed each commit and halved throughput. The monitoring layer (disk utilization, write rate, load average) showed disk activity but could not attribute the slowdown to block IO latency — that required eBPF.

The anomaly was injected deliberately (a known cause), as permitted by the ROADMAP when no natural anomaly occurs; this machine's workload is otherwise too uniform to produce a spontaneous block IO anomaly on schedule.

## Reproducing Each Conclusion

Every claim above is backed by a re-runnable script in `scripts/m4/`:

| Conclusion | Script |
|-----------|--------|
| Baseline throughput | `scripts/m4/run_baseline.sh` |
| Anomaly-run throughput + injected writer | `scripts/m4/run_anomaly.sh` |
| Benchmark is fsync-bound (offcpu) | `scripts/m4/attribution_offcpu.sh` |
| Block IO latency doubles (biolat) | `scripts/m4/attribution_biolat.sh` |
| All four, automated | `scripts/verify_m4.sh` |

`scripts/verify_m4.sh` runs all of the above and asserts: baseline throughput exceeds anomaly throughput, offcpu attributes `sqlite_bench` to the fsync path, and biolat's anomaly median exceeds its baseline median.

## How to Manually Verify

1. Baseline throughput:
   ```bash
   bash scripts/m4/run_baseline.sh
   # expect ~300-360 rows/sec
   ```
2. Anomaly throughput (background writer injected):
   ```bash
   bash scripts/m4/run_anomaly.sh
   # expect noticeably lower rows/sec than baseline
   ```
3. fsync attribution:
   ```bash
   bash scripts/m4/attribution_offcpu.sh
   # expect fdatasync / ext4_sync_file in sqlite_bench's stack
   ```
4. Latency shift:
   ```bash
   bash scripts/m4/attribution_biolat.sh
   # expect anomaly median bucket > baseline median bucket
   ```
5. Full automated check:
   ```bash
   ./scripts/verify_m4.sh   # expect pass=4 fail=0
   ```

## Known Limitations

- The anomaly is injected, not naturally occurring (permitted by ROADMAP M4).
- offcpu prints user addresses raw; attribution here relies on kernel stacks, which are symbolized.
- The benchmark uses synchronous single-row commits by design, to maximize sensitivity to block IO latency; batched commits would amortize fsync and reduce the effect.
