# Exercise 6: User-Space uprobe — Counting malloc Calls

## Goal

Use a uprobe to count how many times `malloc` is called in a specific process by attaching to the `malloc` symbol in libc.

## Reference Command

```bash
bpftrace -e 'uprobe:/lib/x86_64-linux-gnu/libc.so.6:malloc /comm == "ex06_trigger"/ { @count = count(); }'
```

## Expected Output

After running the trigger (which calls `malloc` 100 times), the output should show:

```
@count: 100
```

## Explanation

- `uprobe:/lib/x86_64-linux-gnu/libc.so.6:malloc` — attaches a uprobe to the `malloc` function in the C standard library. When any process calls `malloc`, this probe fires.
- `/comm == "ex06_trigger"/` — filter: only count events from our trigger process.
- `@count = count()` — increment a counter each time `malloc` is called.
- On SIGINT, bpftrace prints: `@count: 100`.

## How to Find the libc Path

```bash
ldd /bin/ls | grep libc
#   linux-vdso.so.1 (0x...)
#   libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x...)
```

## How to Verify the Symbol Exists

```bash
nm -D /lib/x86_64-linux-gnu/libc.so.6 | grep -w malloc
#   00000000000a2b50 T malloc@@GLIBC_2.2.5
```

## Why This Matters

Uprobes let you observe userspace application behavior at the function level without modifying the application's source code, recompiling it, or restarting it. This is useful for profiling library calls (malloc, free, write), application-internal functions, and understanding which code paths consume the most resources.
