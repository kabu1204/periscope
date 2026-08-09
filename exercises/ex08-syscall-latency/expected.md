# Exercise 8: Syscall Latency Histogram

## Goal

Measure the latency distribution of the `openat` syscall — the time from syscall entry to syscall return — using paired enter/exit tracepoints.

## Reference Command

```bash
bpftrace -e '
tracepoint:syscalls:sys_enter_openat /comm == "ex08_trigger"/ { @start[tid] = nsecs; }
tracepoint:syscalls:sys_exit_openat /comm == "ex08_trigger" && @start[tid]/ {
    @latency = hist(nsecs - @start[tid]);
    delete(@start[tid]);
}
'
```

## Expected Output

After running the trigger (20 `openat` calls), the output should show a `@latency` histogram:

```
@latency:
[4K, 8K)            12 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
[8K, 16K)            8 |@@@@@@@@@@@@@@@@@@@@@@@@                            |
```

(Exact values will vary by system and cache state.)

## Explanation

- `tracepoint:syscalls:sys_enter_openat` — fires on `openat` syscall entry. We store the timestamp keyed by `tid` (thread ID).
- `tracepoint:syscalls:sys_exit_openat` — fires on `openat` syscall return. We look up the start time, compute the delta, and add it to a histogram.
- `@start[tid]` — keyed by thread ID (not PID) because multiple threads in the same process can be inside `openat` simultaneously. Using `tid` avoids overwriting one thread's start time with another's.
- `hist(nsecs - @start[tid])` — log2 histogram of the syscall duration in nanoseconds.
- The filter `/comm == "ex08_trigger" && @start[tid]/` ensures we only process exits for our trigger process and for which we have a recorded start time.
- `delete(@start[tid])` — clean up the map entry.

## The Enter/Exit Pattern

This is the fundamental pattern for measuring any syscall's duration with bpftrace:

1. On entry: record `nsecs` keyed by `tid`.
2. On exit: compute `nsecs - @start[tid]`, aggregate, then delete the entry.

This pattern generalizes to any syscall that has both `sys_enter_*` and `sys_exit_*` tracepoints, which is all of them on modern kernels.
