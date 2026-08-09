# Exercise 2: File-Open Tracing

## Goal

Trace which file paths are opened by a specific process using bpftrace.

## Reference Command

```bash
bpftrace -e 'tracepoint:syscalls:sys_enter_openat /comm == "ex02_trigger"/ { printf("%s\n", str(args->filename)); }'
```

## Expected Output

After running the trigger, the output should include:

```
/tmp/ex02_marker_file
```

## Explanation

- `tracepoint:syscalls:sys_enter_openat` — attaches to the `openat` syscall entry tracepoint.
- `args->filename` — the first argument of the `openat` tracepoint, which is a pointer to the filename string.
- `str(args->filename)` — dereferences the userspace pointer and reads the string from the process's memory.
- `printf` — prints the filename immediately (not aggregated into a map).
