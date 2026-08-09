# Exercise 1: Syscall Counting

## Goal

Count how many times the `openat` syscall is made by a specific process, using bpftrace.

## Reference Command

```bash
bpftrace -e 'tracepoint:syscalls:sys_enter_openat /comm == "ex01_trigger"/ { @count = count(); }'
```

## Expected Output

After running the trigger (which calls `openat` exactly 10 times), the output should show:

```
@count: 10
```

## Explanation

- `tracepoint:syscalls:sys_enter_openat` — attaches to the kernel tracepoint that fires on every `openat` syscall entry.
- `/comm == "ex01_trigger"/` — filter: only count events from the process named `ex01_trigger`.
- `@count = count()` — increment a map counter each time the probe fires.
- On SIGINT, bpftrace prints the map: `@count: 10`.
