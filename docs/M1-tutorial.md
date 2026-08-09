# M1 Tutorial: bpftrace for Systems Engineers

> Target reader: someone who understands operating systems and systems programming but has zero eBPF background.
>
> Prerequisites: root access (bpftrace requires `CAP_SYS_ADMIN` and `CAP_BPF` or `CAP_PERFMON`), kernel ≥ 4.18 with BTF, bpftrace installed.

## 1. What Is eBPF?

eBPF (extended Berkeley Packet Filter) is a kernel technology that lets you run small, sandboxed programs inside the kernel at specific events — without writing or loading kernel modules. You write a program, the kernel's verifier checks it for safety (no infinite loops, no out-of-bounds memory access, no kernel panics), and then attaches it to an event source. When that event fires, your program runs in kernel context.

### 1.1 The Three Core Concepts

**Event sources** — the points in the kernel (or userspace) where your program runs. Examples: a kernel function entry (`kprobe`), a kernel tracepoint (a stable hook placed by kernel developers), a userspace function entry (`uprobe`), or a perf event (like a timer or hardware counter).

**Maps** — data structures shared between the eBPF program (running in kernel context) and userspace. A map can be a hash table, a histogram, or a per-CPU array. When your program fires, it writes to maps; the userspace tool (bpftrace) reads them and prints results. Maps are how data gets out of the kernel.

**Verifier** — a static analysis pass in the kernel that checks every eBPF program before it is loaded. The verifier ensures: the program terminates (bounded loops), all memory accesses are in-bounds, and no uninitialized data is used. If a program fails verification, it is rejected at load time — it never runs. This is what makes eBPF safe to run in production: a rejected program cannot crash the kernel.

### 1.2 The bpftrace Model

bpftrace is a high-level language that hides the low-level details of eBPF. You write one-liner scripts; bpftrace compiles them to eBPF bytecode, loads them into the kernel, attaches them to the specified probes, reads the resulting maps, and prints the output. You never write C code, never manage map memory, never deal with the loader directly.

A bpftrace program has this structure:

```
probe /filter/ { action }
```

- **probe** — the event source (e.g., `kprobe:vfs_read`, `tracepoint:syscalls:sys_enter_openat`)
- **filter** (optional) — a predicate that must be true for the action to run (e.g., `/pid == 1234/`)
- **action** — what to do when the probe fires (e.g., `@count = count()`, `printf("%s\n", comm)`)

## 2. bpftrace Syntax Essentials

### 2.1 Probes

A probe name has the form `type:identifier`:

| Type | Syntax | Example |
|------|--------|---------|
| kprobe | `kprobe:function_name` | `kprobe:vfs_read` |
| kretprobe | `kretprobe:function_name` | `kretprobe:vfs_read` |
| tracepoint | `tracepoint:category:event` | `tracepoint:syscalls:sys_enter_openat` |
| uprobe | `uprobe:binary:function` | `uprobe:/lib/x86_64-linux-gnu/libc.so.6:malloc` |
| uretprobe | `uretprobe:binary:function` | `uretprobe:/lib/x86_64-linux-gnu/libc.so.6:malloc` |
| profile | `profile:hz:rate` | `profile:hz:99` |
| interval | `interval:s:seconds` | `interval:s:1` |
| BEGIN | `BEGIN` | runs once at startup |
| END | `END` | runs once at shutdown (prints maps by default) |

### 2.2 Built-in Variables

| Variable | Meaning |
|----------|---------|
| `pid` | process ID (kernel PID) |
| `tid` | thread ID |
| `comm` | process name (command name, 16 chars max) |
| `uid` | user ID |
| `cpu` | CPU ID |
| `kstack` | kernel stack trace |
| `ustack` | userspace stack trace |
| `arg0`..`argN` | probe arguments (for kprobes, these are function arguments; for tracepoints, use `args->field_name`) |
| `retval` | return value (in kretprobes) |

### 2.3 Maps (Aggregations)

Maps are variables prefixed with `@`. They are the primary way to collect and aggregate data.

```
@count = count()          # increment a counter
@sum = sum(arg1)          # accumulate a sum
@avg = avg(arg1)          # running average
@min = min(arg1)          # minimum value seen
@max = max(arg1)          # maximum value seen
@hist(arg1)               # log2 histogram of arg1 values
@lhist(arg1, min, max, step)  # linear histogram
```

When using a map with a key, bpftrace groups by that key:

```
@syscalls[comm] = count()  # count syscalls per process name
@latency[pid] = hist(args->delta)  # histogram of latency per process
```

### 2.4 printf

For immediate output (not aggregated), use `printf`:

```
tracepoint:syscalls:sys_enter_openat {
    printf("%s (pid %d) opened %s\n", comm, pid, str(args->filename));
}
```

`str()` is required to read string pointers from kernel or userspace memory — it dereferences the pointer and copies the string into bpftrace's output buffer.

### 2.5 Filters

Filters are predicates in slashes after the probe name:

```
tracepoint:syscalls:sys_enter_openat /comm == "cat"/ {
    printf("cat called openat\n");
}
```

Multiple probes can share an action:

```
kprobe:vfs_read, kprobe:vfs_write {
    @io[comm] = count();
}
```

### 2.6 Running bpftrace

```bash
# One-liner
bpftrace -e 'BEGIN { printf("hello\n"); exit(); }'

# Script file
bpftrace script.bt

# With a timeout (SIGINT causes maps to print before exit)
timeout -s INT 5 bpftrace -e 'tracepoint:syscalls:sys_enter_openat { @count = count(); }'
```

## 3. Probe Types in Depth

### 3.1 kprobe / kretprobe

A **kprobe** attaches to the entry of a kernel function. The function's arguments are available as `arg0`, `arg1`, etc. (architecture-dependent; on x86_64, `arg0` is `rdi`, `arg1` is `rsi`, etc., per the System V AMD64 calling convention).

A **kretprobe** attaches to the return of a kernel function. The return value is available as `retval`.

```
# Count how many times vfs_read is called per process
kprobe:vfs_read { @reads[comm] = count(); }

# Measure vfs_read return value (bytes read)
kretprobe:vfs_read { @bytes[comm] = sum(retval); }
```

**Limitation**: kprobes attach to kernel functions by name. Kernel functions can be inlined or renamed between versions, making kprobes fragile. Prefer tracepoints when one is available.

### 3.2 tracepoint

A **tracepoint** is a stable hook placed by kernel developers at well-defined points in the kernel. Unlike kprobes, tracepoints have a stable ABI: their arguments are accessible by name via `args->field_name`.

To discover available tracepoints and their argument formats:

```bash
# List all tracepoints matching a pattern
bpftrace -l 'tracepoint:syscalls:*open*'

# Show arguments for a specific tracepoint
bpftrace -lv tracepoint:syscalls:sys_enter_openat
```

Example output:
```
tracepoint:syscalls:sys_enter_openat
    int __syscall_nr;
    const char __user * filename;
    int flags;
    umode_t mode;
```

```
# Trace which files are opened
tracepoint:syscalls:sys_enter_openat {
    printf("%s: %s\n", comm, str(args->filename));
}
```

### 3.3 uprobe / uretprobe

A **uprobe** attaches to the entry of a userspace function in a specific binary. The binary path and function name must be specified.

```
# Count calls to malloc per process
uprobe:/lib/x86_64-linux-gnu/libc.so.6:malloc {
    @malloc_calls[comm] = count();
}
```

To find available symbols in a binary:

```bash
nm -D /lib/x86_64-linux-gnu/libc.so.6 | grep malloc
# or
bpftrace -l 'uprobe:/lib/x86_64-linux-gnu/libc.so.6:*malloc*'
```

**uprobe arguments** are available as `arg0`, `arg1`, etc., following the userspace calling convention (System V AMD64 on x86_64 Linux).

### 3.4 USDT (User Statically Defined Tracing)

USDT probes are explicit tracepoints inserted by application developers using `DTRACE_PROBE()` macros. They are available in some applications (e.g., MySQL, PostgreSQL, libpthread). bpftrace can attach to them:

```
usdt:/path/to/binary:provider:probe { ... }
```

USDT probes are less common than uprobes; they require the application to have been built with USDT support. In this tutorial, we focus on uprobes, which work with any binary that has symbols.

## 4. Aggregations and Primitives

### 4.1 count()

The most common aggregation — simply increments a counter each time the probe fires:

```
@syscalls[comm] = count()
```

On exit (SIGINT or `exit()`), bpftrace prints the map sorted by value descending.

### 4.2 hist()

Produces a log2 power-of-two histogram. Ideal for latency distributions, where values span multiple orders of magnitude:

```
@latency = hist(nsecs - @start[tid])
```

Output format:
```
@latency:
[1K, 2K)            4 |@                                                   |
[2K, 4K)           12 |@@@@@@@@@@                                          |
[4K, 8K)           38 |@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                     |
```

Each bracket shows a range; the bar length is proportional to the count in that bucket.

### 4.3 lhist()

A linear histogram with fixed bucket width. Useful when the value range is narrow and uniform:

```
@hist = lhist(arg1, 0, 100, 10)  # buckets: 0-10, 10-20, ..., 90-100
```

### 4.4 arg access

- **kprobe**: `arg0`, `arg1`, ... — function arguments (register-based)
- **kretprobe**: `retval` — function return value
- **tracepoint**: `args->field_name` — stable, named arguments (discover with `bpftrace -lv`)
- **uprobe**: `arg0`, `arg1`, ... — userspace function arguments
- **String pointers**: use `str(ptr)` to read a kernel or userspace string; use `buf(ptr, len)` for raw byte buffers

### 4.5 Timing pattern

To measure the duration of an operation, store a timestamp at entry and compute the delta at return:

```
kprobe:vfs_read { @start[tid] = nsecs; }
kretprobe:vfs_read /@start[tid]/ {
    @latency = hist(nsecs - @start[tid]);
    delete(@start[tid]);
}
```

`nsecs` is a built-in giving the current time in nanoseconds. `tid` (thread ID) is used as the map key because multiple threads can be inside `vfs_read` simultaneously — using `tid` avoids overwriting one thread's start time with another's.

### 4.6 exit()

The `exit()` function stops all probes, runs any `END` probe, prints all maps, and terminates bpftrace. When you send SIGINT (Ctrl+C) to bpftrace, it effectively calls `exit()`.

## 5. Practical Workflow

1. **Discover probes**: `bpftrace -l 'pattern'` or `bpftrace -lv 'probe'` (to see arguments)
2. **Write the one-liner**: start with a `printf` to confirm the probe fires
3. **Add aggregation**: replace `printf` with `@map = count()` or `@map = hist(value)`
4. **Add filter**: narrow to the process or condition you care about
5. **Run with timeout**: `timeout -s INT N bpftrace -e '...'` to run for N seconds
6. **Interpret output**: read the histogram or map output; look for unexpected patterns

## 6. Exercises

The `exercises/` directory contains 8 exercises. Each has three files:

- **`trigger.sh`** — a script that produces the behavior you should observe
- **`expected.md`** — the reference bpftrace command and what the output should look like
- **`verify.sh`** — an automated check that runs the bpftrace command and trigger together, then verifies the output

Start by reading `expected.md` to understand the goal, try to write the bpftrace command yourself, then run `./verify.sh` to check your answer. If you get stuck, the reference command in `expected.md` is the answer key.

The exercises cover: syscall counting, file-open tracing, block IO latency, scheduling latency, short-lived process capture, user-space uprobe, signal delivery, and syscall latency.
