# Exercise 4: Scheduling Latency Histogram

## Goal

Measure the distribution of scheduling latency — the time from when a thread becomes ready (woken up) to when it actually starts running on a CPU.

## Reference Command

```bash
bpftrace -e '
tracepoint:sched:sched_wakeup { @start[args->pid] = nsecs; }
tracepoint:sched:sched_switch /@start[args->next_pid]/ {
    @latency = hist(nsecs - @start[args->next_pid]);
    delete(@start[args->next_pid]);
}
'
```

## Expected Output

After running the trigger (4 CPU-bound processes competing for 2 CPUs), the output should show a `@latency` histogram with most entries in the microsecond range:

```
@latency:
[1K, 2K)            531 |@@@@@@@@@@@@@@@                                     |
[2K, 4K)           1820 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
[4K, 8K)            979 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                      |
```

(Exact values will vary by system load and CPU count.)

## Explanation

- `tracepoint:sched:sched_wakeup` — fires when a thread is woken up (transitions from sleeping/blocked to runnable). We record the timestamp keyed by PID.
- `tracepoint:sched:sched_switch` — fires on every context switch. `args->next_pid` is the PID of the thread that is about to run on the CPU. We look up the start time, compute the scheduling delay, and add it to a histogram.
- `@start[args->pid]` — a map keyed by PID, correlating wakeup events with subsequent schedule events.
- `hist(nsecs - @start[args->next_pid])` — log2 histogram of the scheduling latency in nanoseconds.
- The filter `/@start[args->next_pid]/` ensures we only process switches for threads we recorded a wakeup for.
- `delete(@start[args->next_pid])` — clean up to prevent map growth.

## Why This Matters

Scheduling latency is a key indicator of CPU saturation. When more threads are runnable than available CPUs, threads must wait in the run queue. A rightward shift in this histogram under load indicates that the system cannot keep up with the workload's CPU demand.
