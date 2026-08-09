# Exercise 3: Block IO Latency Histogram

## Goal

Measure the latency distribution of block IO completion events (time from request issue to completion) using bpftrace tracepoints.

## Reference Command

```bash
bpftrace -e '
tracepoint:block:block_rq_issue { @start[args->sector] = nsecs; }
tracepoint:block:block_rq_complete /@start[args->sector]/ {
    @latency = hist(nsecs - @start[args->sector]);
    delete(@start[args->sector]);
}
'
```

## Expected Output

After running the trigger (100 direct 4K writes), the output should show a `@latency` histogram with data in the sub-millisecond range:

```
@latency:
[256K, 512K)          8 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@|
[512K, 1M)            5 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                      |
```

(Exact bucket positions and counts will vary by hardware and load.)

## Explanation

- `tracepoint:block:block_rq_issue` — fires when a block IO request is submitted to the device driver. We store the timestamp `nsecs` keyed by sector number.
- `tracepoint:block:block_rq_complete` — fires when a block IO request completes. We look up the start time by sector, compute the delta, and add it to a log2 histogram.
- `@start[args->sector]` — a map keyed by sector number, used to correlate issue and completion events.
- `hist(nsecs - @start[args->sector])` — a power-of-two histogram of the latency in nanoseconds.
- `delete(@start[args->sector])` — clean up the map entry to avoid memory growth.
- The filter `/@start[args->sector]/` ensures we only process completions for which we recorded a start time.
