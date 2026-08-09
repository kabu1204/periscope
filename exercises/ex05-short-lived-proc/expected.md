# Exercise 5: Short-Lived Process Capture

## Goal

Detect short-lived processes that start and exit so quickly that tools like `ps` or `top` would miss them. This is a classic use case for eBPF: the kernel fires a tracepoint on every `execve` syscall, so no process can escape detection.

## Reference Command

```bash
bpftrace -e 'tracepoint:sched:sched_process_exec /comm == "ex05_slp"/ { printf("exec: pid=%d comm=%s\n", args->pid, comm); }'
```

## Expected Output

After running the trigger (which execs the short-lived process 3 times), the output should show:

```
exec: pid=<N> comm=ex05_slp
exec: pid=<N> comm=ex05_slp
exec: pid=<N> comm=ex05_slp
```

## Explanation

- `tracepoint:sched:sched_process_exec` — fires when a process calls `execve` (replaces its image with a new program). This is the moment a new program starts running under an existing PID.
- `args->pid` — the PID of the process (available as a named tracepoint argument).
- `comm` — the new command name (set by `execve`, limited to 16 characters by the kernel).
- The filter `/comm == "ex05_slp"/` narrows to our specific process name. Note: `comm` is truncated to 16 characters by the kernel, so the binary name must be ≤16 chars.
- `printf` — prints immediately, capturing each execution event.

## Why This Matters

Traditional monitoring tools sample at intervals (e.g., 1-second `ps` snapshots). A process that starts, does work, and exits within that interval is invisible. eBPF tracepoints fire on every event with zero sampling overhead, making them ideal for detecting short-lived processes, orphaned children, or rapid exec loops.
