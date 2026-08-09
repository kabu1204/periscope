# Design Note: M3 — Run Queue Latency + Off-CPU Attribution

## Conclusion First

M3 is complete. Two custom Rust eBPF tools were built using libbpf-rs (D-001): `tools/runqlat/` (run queue latency histogram, equivalent to bcc `runqlat`) and `tools/offcpu/` (off-CPU time by stack, equivalent to bcc `offcputime`). `scripts/verify_m3.sh` verifies both against the bcc oracles and three known injection scenarios. All checks pass (5/5).

## Background and Principles

### Run Queue Latency

Run queue latency is the time from when a task becomes runnable to when it actually starts running on a CPU. A high value means tasks are waiting because all CPUs are busy — a direct signal of CPU saturation. It answers the question: "is my workload slow because it is waiting for CPU, or because it is doing something else (IO, locks)?"

Two events define the measurement:
- **Enqueue**: `sched_wakeup` / `sched_wakeup_new` fire when a task is woken and becomes runnable. Additionally, when `sched_switch` shows the outgoing task (`prev`) still in `TASK_RUNNING` state, it was preempted and immediately re-enqueued — its wait starts at that switch.
- **Dequeue**: `sched_switch` fires when the CPU switches to a new task (`next`). If `next` has a recorded enqueue timestamp, the difference is its run queue latency.

### Off-CPU Attribution

Off-CPU time is the time a task spends not running because it is blocked (on IO, locks, timers, etc.). Summing off-CPU time per stack answers: "where is my workload spending its blocked time?"

The measurement is entirely within `sched_switch`:
- When `prev` is scheduled out, record the timestamp keyed by its pid.
- When `next` is scheduled in, compute the delta, capture next's kernel and user stacks, and accumulate the delta under a key of (pid, comm, kernel stack id, user stack id).

The idle task (pid 0) is excluded: its off-CPU time is idle time, not blocking. bcc `offcputime` does the same.

## Design

### Architecture

Both tools follow the same structure as M2's biolat:

```
┌─────────────────────────────────────────────────┐
│  tools/<name>/src/bpf/<name>.bpf.c  (BPF, C)    │
│  tracepoint handlers → maps (hist / counts)     │
└──────────────────────┬──────────────────────────┘
                       │ compiled by clang (build.rs, SkeletonBuilder)
                       ▼
┌─────────────────────────────────────────────────┐
│  tools/<name>/src/main.rs (Userspace, Rust)     │
│  SkelBuilder::open() → load() → attach()        │
│  sleep(duration) → read maps → print report     │
└─────────────────────────────────────────────────┘
```

`vmlinux.h` is generated from kernel BTF at build time by `build.rs` (same as M2). Both tools take `-d SECONDS` to trace for a fixed duration and print on exit.

### runqlat

- **BPF** (`runqlat.bpf.c`): attaches to `tracepoint/sched/sched_wakeup`, `sched_wakeup_new`, and `sched_switch`. A hash map (`start`) records when each task became runnable (keyed by pid). On `sched_switch`, the latency for `next` is computed and stored in a log2 histogram (microseconds). The `prev_state == TASK_RUNNING` case is handled: a preempted task's wait starts when it is switched out.
- **Output**: bcc-compatible log2 histogram in microseconds.

### offcpu

- **BPF** (`offcpu.bpf.c`): attaches to `tracepoint/sched/sched_switch`. A hash map (`start`) records schedule-out timestamps (keyed by pid). On schedule-in, the delta is computed and the kernel and user stacks are captured via `bpf_get_stackid` into a shared `stackmap`. The (pid, comm, kernel_stack_id, user_stack_id) key accumulates total off-CPU microseconds in a `counts` hash map. The idle task is skipped.
- **Userspace** (`main.rs`): drains the counts map, sorts by total off-CPU time, and prints each stack. Kernel addresses are symbolized from `/proc/kallsyms`; user addresses are printed raw (symbolizing user stacks requires per-process symbol tables, which bcc resolves with debug info — a future enhancement, not required for attribution to a known stack).
- **Output**: bcc-compatible stack list with per-stack total microseconds.

## Verification

**Oracles**: bcc `runqlat-bpfcc` and `offcputime-bpfcc`.

**Injection scenarios** (`scripts/verify_m3.sh`, `scripts/m3/`):

- **Scenario A — CPU saturation** (`cpu_burn.sh`): spawns 2x as many CPU-bound processes as CPUs. runqlat must show significantly elevated queuing vs an idle baseline.
- **Scenario B — lock contention** (`lock_contention.c`): 8 threads fight over one pthread mutex. offcpu must attribute the dominant off-CPU stack to futex.
- **Scenario C — synchronous disk wait** (`sync_write.sh`): fio sync direct-IO writes to a block-backed file. offcpu must attribute the off-CPU stack to the IO wait path.

**Acceptance** (per ROADMAP): magnitudes within 2x of bcc; all three scenarios attributed to the pre-labeled cause.

```
$ bash scripts/verify_m3.sh
=== Scenario A: CPU saturation (runqlat) ===
  baseline: peak=2us tail=29/1000  saturated: our peak=4us tail=178/1000  oracle peak=4us
  PASS: runqlat shows elevated queuing under CPU saturation
  PASS: runqlat matches bcc oracle within 2x (peak and tail)
=== Scenario B: lock contention (offcpu) ===
  PASS: offcpu attributes lock contention to futex stack
  PASS: bcc offcputime oracle attributes lock contention to futex stack
=== Scenario C: synchronous disk wait (offcpu) ===
  PASS: offcpu attributes synchronous disk wait to IO stack
verify_m3.sh results: pass=5 fail=0
```

### Note on the Scenario A elevation signal

The peak bucket alone is not a valid saturation signal: woken daemons produce many short waits that keep the peak low even under saturation, for bcc as well as our tool. The elevation check therefore compares the fraction of samples at or above 64us (the "tail") between baseline and saturated runs; the oracle check compares both peak and tail fraction. The two tools' saturated distributions match closely.

## How to Manually Verify

1. **Build the tools**:
   ```bash
   cd tools/runqlat && cargo build --release
   cd ../offcpu && cargo build --release
   ```

2. **runqlat, idle vs saturated** (two terminals):
   ```bash
   # Terminal 1:
   ./tools/runqlat/target/release/runqlat -d 8
   # Terminal 2 (after 1s): oversubscribe the CPUs
   for i in 1 2 3 4; do yes > /dev/null & done; sleep 6; kill %1 %2 %3 %4
   # Compare the histogram with an idle run: the tail (>=64us) grows.
   ```

3. **runqlat vs bcc oracle**:
   ```bash
   ./tools/runqlat/target/release/runqlat -d 10 &
   timeout -s INT 10 runqlat-bpfcc &
   # generate load, then wait; compare the histograms.
   ```

4. **offcpu vs bcc oracle under lock contention**:
   ```bash
   ./tools/offcpu/target/release/offcpu -d 8 &
   timeout -s INT 8 offcputime-bpfcc &
   sleep 1
   ./scripts/m3/lock_contention 6 8
   wait
   # Both outputs should show futex in the dominant stack.
   ```

5. **Run the automated verification**:
   ```bash
   ./scripts/verify_m3.sh
   # Expected: pass=5 fail=0
   ```

## Known Limitations

- **User stacks not symbolized (offcpu)**: user-space addresses are printed raw. Attribution to a known kernel stack (futex, IO wait) is unaffected. Symbolizing user stacks requires per-process symbol tables; bcc resolves these via debug info.
- **Stack depth capped at 127**: the kernel's `perf_event_max_stack` on this machine is 127; deeper stacks are truncated (same as bcc's default).
- **runqlat per-task, not per-cpu-queue**: latency is measured per task across wakeups, equivalent to bcc's default (per-pid) mode. Per-CPU breakdowns are not implemented.
- **Idle-task exclusion (offcpu)**: off-CPU time of pid 0 is not reported (same as bcc).
