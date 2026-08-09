# Design Note: M1 — bpftrace Tutorial + Exercise Set

## Conclusion First

M1 is complete. A tutorial document (`docs/M1-tutorial.md`) covers the eBPF program model (event sources, maps, verifier), bpftrace syntax, probe types (kprobe/uprobe/tracepoint/USDT), and aggregation primitives (count/hist/arg access). Eight exercises were created under `exercises/`, each with `trigger.sh`, `expected.md`, and `verify.sh`. The `ci_report.sh` M1 section automatically runs all `verify.sh` scripts; all 8 pass. Coverage spans syscall counting, file-open tracing, block IO latency, scheduling latency, short-lived process capture, user-space uprobe, signal delivery, and syscall latency.

## Background and Principles

### eBPF Program Model

eBPF programs run inside the kernel at specific event points (probes). Three concepts govern the model:

- **Event sources**: the attachment points — kernel function entry/return (kprobe/kretprobe), stable kernel hooks (tracepoints), userspace function entry/return (uprobe/uretprobe), and timers (profile/interval).
- **Maps**: shared data structures (hash tables, histograms, arrays) between the in-kernel program and userspace. Maps are how data exits the kernel.
- **Verifier**: a static analysis pass that rejects unsafe programs (infinite loops, out-of-bounds access) at load time. This is what makes eBPF safe for production use.

bpftrace is a high-level language that compiles one-liner scripts into eBPF bytecode, handles map creation and reading, and prints results — hiding all low-level details from the user.

### Why bpftrace for the Tutorial Phase

bpftrace is the fastest path from "I want to observe X" to "I have data about X". A one-liner like `bpftrace -e 'tracepoint:syscalls:sys_enter_openat { @count = count(); }'` is self-contained: no compilation, no loader code, no map management. This makes it ideal for teaching eBPF concepts without the overhead of a full toolchain setup. The custom Rust eBPF tools (M2, M3) will build on the same kernel facilities, so the mental model transfers directly.

## Design

### Tutorial Structure

The tutorial (`docs/M1-tutorial.md`) is organized as:

1. **What Is eBPF?** — the three core concepts (event sources, maps, verifier) in plain language.
2. **bpftrace Syntax** — probes, built-in variables, maps/aggregations, printf, filters, running commands.
3. **Probe Types in Depth** — kprobe, tracepoint, uprobe, USDT — with syntax, examples, and trade-offs (kprobe fragility vs. tracepoint stability).
4. **Aggregations and Primitives** — count, hist, lhist, arg access, the timing pattern (store nsecs at entry, compute delta at return).
5. **Practical Workflow** — discover probes, write one-liner, add aggregation, add filter, run with timeout, interpret output.
6. **Exercises** — pointer to the 8 exercises with instructions.

### Exercise Design

Each exercise follows a three-file pattern:

| File | Purpose |
|------|---------|
| `trigger.sh` | Produces the behavior to be observed (compiles and runs a C program or shell command) |
| `expected.md` | Reference answer: the bpftrace command, expected output, and explanation |
| `verify.sh` | Automated check: starts bpftrace, runs the trigger, verifies the output matches the expected answer |

All triggers produce deterministic results (exact counts or guaranteed histogram output) so that `verify.sh` can check for known answers.

### Exercise Coverage

| # | Exercise | Probe Type | Oracle (known answer) |
|---|----------|-----------|---------------------|
| 1 | Syscall counting | tracepoint:syscalls | `openat` count = exactly 10 |
| 2 | File-open tracing | tracepoint:syscalls | `/tmp/ex02_marker_file` appears in output |
| 3 | Block IO latency | tracepoint:block | `@latency` histogram with data |
| 4 | Scheduling latency | tracepoint:sched | `@latency` histogram with data |
| 5 | Short-lived process capture | tracepoint:sched | Process name appears ≥3 times |
| 6 | User-space uprobe | uprobe:libc | `malloc` count = exactly 100 |
| 7 | Signal delivery | tracepoint:signal | `sig=10` appears ≥5 times |
| 8 | Syscall latency | tracepoint:syscalls (enter+exit) | `@latency` histogram with data |

### Static Linking for Deterministic Tracing

Trigger programs that need precise syscall counting or filename reading use `-static` linking. This avoids two issues observed during development:

1. **Inflated counts**: dynamically-linked binaries trigger `openat` calls from `ld.so` during library loading, which bpftrace counts alongside the user's calls. Static linking eliminates these extra calls.
2. **str() failures**: bpftrace's `str()` function sometimes fails to read userspace string pointers from dynamically-linked code. With static linking, the string addresses are in a memory region that bpftrace can reliably access.

The uprobe exercise (ex06) uses dynamic linking (required, since it probes `libc.so.6:malloc`), but this is not affected because it counts probe firings rather than reading strings.

### Process Name Length

The kernel's `comm` field is limited to 16 characters (15 + null terminator). Binary names in trigger scripts are kept ≤16 characters to ensure the `comm` filter in bpftrace matches correctly. Binary names that exceeded this limit (e.g., `ex05_shortlived_proc` at 20 chars) were shortened (e.g., `ex05_slp`).

## Verification

**Oracle**: Known answers (per `ROADMAP.md` M1 acceptance criteria).

```
$ bash ci_report.sh m1
PASS  M1: exercises/ex01-syscall-count/verify.sh
PASS  M1: exercises/ex02-file-open-trace/verify.sh
PASS  M1: exercises/ex03-block-io-latency/verify.sh
PASS  M1: exercises/ex04-sched-latency/verify.sh
PASS  M1: exercises/ex05-short-lived-proc/verify.sh
PASS  M1: exercises/ex06-uprobe-malloc/verify.sh
PASS  M1: exercises/ex07-signal-delivery/verify.sh
PASS  M1: exercises/ex08-syscall-latency/verify.sh
pass: 8  fail: 0
```

Each `verify.sh` starts bpftrace with the reference command, runs the trigger, sends SIGINT to bpftrace (causing map output), and checks the output for the known answer.

## How to Manually Verify

1. **Run all exercises automatically**:
   ```bash
   ./ci_report.sh m1
   # Expected: pass: 8  fail: 0
   ```

2. **Run a single exercise manually** (example: exercise 1):
   ```bash
   # Terminal 1: start bpftrace
   bpftrace -e 'tracepoint:syscalls:sys_enter_openat /comm == "ex01_trigger"/ { @count = count(); }'
   # Terminal 2: run the trigger
   cd exercises/ex01-syscall-count && bash trigger.sh
   # Go back to Terminal 1 and press Ctrl+C
   # Expected: @count: 10
   ```

3. **Verify bpftrace is installed**:
   ```bash
   bpftrace --version
   # Expected: bpftrace v0.23.2 (or compatible)
   ```

4. **Check the tutorial is readable**:
   ```bash
   wc -l docs/M1-tutorial.md
   # Expected: > 200 lines
   head -5 docs/M1-tutorial.md
   # Expected: "# M1 Tutorial: bpftrace for Systems Engineers"
   ```

## Known Limitations

- **Root required**: bpftrace requires root (or `CAP_SYS_ADMIN` + `CAP_BPF`). The exercises cannot run as a non-root user.
- **Static linking**: trigger programs for exercises 1, 2, 5, and 8 are compiled with `-static` to ensure deterministic results. This means the trigger compilation step takes slightly longer, but the resulting binary is self-contained.
- **Block IO exercise**: on systems with no physical disk (e.g., pure memory filesystems), the block IO tracepoints may not fire. The trigger uses `dd ... oflag=direct` to force real block IO, but on fully virtualized environments with no backing device, the histogram may be empty.
- **Scheduling latency exercise**: requires multiple competing threads. The trigger spawns 4 `yes` processes, but on a single-CPU system the histogram shape will differ from a multi-CPU system.
- **Signal exercise**: the `signal:signal_generate` tracepoint fires when the signal is generated (queued), not when it is delivered to the handler. On some kernel configurations, additional signals may appear (e.g., `sig=17` for SIGCHLD on process exit).
- **bpftrace version**: tested with bpftrace v0.23.2 on kernel 6.12.95. Some syntax (e.g., `str(args->filename, 64)`) may differ on older versions.
