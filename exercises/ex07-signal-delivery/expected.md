# Exercise 7: Signal Delivery Tracing

## Goal

Trace signal delivery to processes using the kernel's `signal:signal_generate` tracepoint, and verify that the expected signal (SIGUSR1 = 10) is observed.

## Reference Command

```bash
bpftrace -e 'tracepoint:signal:signal_generate /comm == "ex07_trigger"/ { printf("sig=%d pid=%d\n", args->sig, args->pid); }'
```

## Expected Output

After running the trigger (which sends itself SIGUSR1 5 times), the output should show:

```
sig=10 pid=<N>
sig=10 pid=<N>
sig=10 pid=<N>
sig=10 pid=<N>
sig=10 pid=<N>
```

## Explanation

- `tracepoint:signal:signal_generate` — fires when the kernel generates a signal for delivery to a process. This is the point where the signal is queued for delivery (not yet handled by the process).
- `args->sig` — the signal number (available as a named tracepoint argument). SIGUSR1 is 10 on Linux x86_64.
- `args->pid` — the PID of the target process.
- `comm` — the process name, used in the filter to narrow to our trigger process.
- `printf` — prints each signal event immediately.

## Signal Number Reference

| Name | Number |
|------|--------|
| SIGHUP | 1 |
| SIGINT | 2 |
| SIGKILL | 9 |
| SIGUSR1 | 10 |
| SIGUSR2 | 12 |
| SIGTERM | 15 |

## Why This Matters

Signal tracing is useful for debugging inter-process communication, investigating unexpected process termination, and understanding signal-driven application behavior. Traditional tools show signal delivery only after the fact (e.g., in logs); eBPF tracepoints capture every signal event in real time with full process context.
