# Design Note: M2 — Block IO Latency Histogram

## Conclusion First

M2 is complete. A custom Rust eBPF tool (`tools/biolat/`) was built using libbpf-rs (D-001) that collects block IO completion latency and outputs a log2 histogram, equivalent to bcc `biolatency`. The tool was verified against the bcc oracle (`biolatency-bpfcc`) using a fixed-parameter dd workload (5 runs). All peak positions match within the 2x acceptance criterion. `ci_report.sh` M2 section passes (4/4: fmt, clippy, build, oracle comparison).

## Background and Principles

### Block IO Latency

Block IO latency is the time from when an IO request enters the block layer to when the device signals completion. Measuring this latency distribution reveals storage performance characteristics: the peak position indicates the typical latency, and the tail (P99) shows worst-case behavior.

### Tracepoint Selection

The kernel exposes several block IO tracepoints. The key challenge is finding a pair that correctly correlates the start and end of each IO request:

| Tracepoint | Fires When | Sector Field |
|------------|-----------|--------------|
| `block:block_bio_queue` | Bio enters request queue | `sector` |
| `block:block_rq_issue` | Request submitted to driver | `sector` (may differ from completion) |
| `block:block_io_start` | IO accounting start | `sector` (matches completion) |
| `block:block_rq_complete` | Request completes | `sector` (may differ from issue) |
| `block:block_io_done` | IO accounting end | `sector` (matches start) |

Initial implementation used `block_rq_issue` + `block_rq_complete`, but sectors did not match reliably (some completions reported sector 0 or -1). Switching to `block_io_start` + `block_io_done` — the same pair used by bcc `biolatency` on modern kernels — resolved this issue. These tracepoints fire at the IO accounting boundaries, where the sector is consistent between start and done.

### Log2 Histogram

The histogram uses power-of-two buckets: bucket index N covers `2^(N-1)` to `2^N - 1` microseconds. This naturally handles latencies spanning multiple orders of magnitude (sub-microsecond to milliseconds). The `log2_bucket` helper computes the index using `__builtin_clzll` (count leading zeros) for O(1) bucket assignment.

## Design

### Technology Selection (D-001)

**libbpf-rs** was chosen over aya for the following reasons:
- BTF is available on the target kernel, enabling CO-RE.
- libbpf-rs uses the same libbpf skeleton mechanism as bcc, making oracle comparison fair.
- BPF programs are written in C (standard approach, well-documented).
- Available as Debian packages and via crates.io.

See `DECISIONS.md` D-001 for the full rationale.

### Architecture

```
┌─────────────────────────────────────────────────┐
│  tools/biolat/src/bpf/biolat.bpf.c  (BPF, C)    │
│                                                  │
│  tracepoint:block:block_io_start                 │
│    → store nsecs in hash map keyed by sector     │
│                                                  │
│  tracepoint:block:block_io_done                  │
│    → lookup start by sector                      │
│    → compute delta (ns) → convert to us         │
│    → increment log2 bucket in array map         │
│    → delete start entry                          │
│                                                  │
│  Maps: start (HASH), hist_map (ARRAY)            │
└──────────────────────┬──────────────────────────┘
                       │ compiled by clang
                       ▼
┌─────────────────────────────────────────────────┐
│  build.rs (SkeletonBuilder)                      │
│  → compiles biolat.bpf.c → biolat.bpf.o          │
│  → generates biolat.skel.rs (embeds BPF object)  │
└──────────────────────┬──────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│  tools/biolat/src/main.rs (Userspace, Rust)      │
│                                                  │
│  BiolatSkelBuilder::open() → load() → attach()  │
│  sleep(duration)                                 │
│  print_histogram(): read hist_map, format output │
└─────────────────────────────────────────────────┘
```

### Build System

The `build.rs` script uses `libbpf_cargo::SkeletonBuilder` to:
1. Compile `biolat.bpf.c` with clang (including `vmlinux.h` and `bpf_helpers.h`).
2. Generate a Rust skeleton module (`biolat.skel.rs`) that embeds the BPF object data and provides typed access to maps and programs.

The skeleton is included in `main.rs` via `include!(concat!(env!("OUT_DIR"), "/biolat.skel.rs"))`.

### vmlinux.h

Generated from kernel BTF: `bpftool btf dump file /sys/kernel/btf/vmlinux format c > src/bpf/vmlinux.h` (127,795 lines). This provides CO-RE type definitions for the BPF program.

### Output Format

The histogram output matches bcc `biolatency` format:

```
     usecs               : count     distribution
      256 -> 511        : 23       |########################################|
      512 -> 1023       : 20       |##################################      |
```

## Verification

**Oracle**: bcc `biolatency-bpfcc -d vda`

**Method**: run both tools in parallel under the same dd workload (200 × 4K direct writes), 5 runs. Compare the peak bucket position (the bucket with the highest count).

**Acceptance criterion**: peak positions within 2x (adjacent log2 buckets accepted).

```
$ bash scripts/verify_m2.sh
--- Run 1/5 ---  PASS: peak positions match (our=512 oracle=512)
--- Run 2/5 ---  PASS: peak positions match (our=256 oracle=256)
--- Run 3/5 ---  PASS: peak positions match (our=512 oracle=512)
--- Run 4/5 ---  PASS: peak positions match (our=512 oracle=256)
--- Run 5/5 ---  PASS: peak positions match (our=256 oracle=256)
pass=5 fail=0
```

```
$ bash ci_report.sh m2
PASS  M2: biolat cargo fmt
PASS  M2: biolat cargo clippy
PASS  M2: biolat cargo build --release
PASS  M2: biolat oracle comparison
pass: 4  fail: 0
```

## How to Manually Verify

1. **Build the tool**:
   ```bash
   cd tools/biolat && cargo build --release
   ```

2. **Run the tool and a workload** (two terminals):
   ```bash
   # Terminal 1:
   ./tools/biolat/target/release/biolat -d 10
   # Terminal 2:
   dd if=/dev/zero of=/tmp/test bs=4k count=200 oflag=direct && rm /tmp/test
   # Wait for Terminal 1 to finish (10s). You should see a histogram.
   ```

3. **Compare with the bcc oracle**:
   ```bash
   # Start both in parallel:
   ./tools/biolat/target/release/biolat -d 8 &
   timeout -s INT 8 biolatency-bpfcc -d vda &
   sleep 1
   dd if=/dev/zero of=/tmp/test bs=4k count=200 oflag=direct && rm /tmp/test
   wait
   # Compare the peak bucket positions in both outputs.
   ```

4. **Run the automated verification**:
   ```bash
   ./ci_report.sh m2
   # Expected: pass: 4  fail: 0
   ```

5. **Check code quality**:
   ```bash
   cd tools/biolat
   cargo fmt -- --check     # should pass
   cargo clippy -- -D warnings  # should pass
   ```

## Known Limitations

- **Sector-based keying**: requests are correlated by sector number. If two in-flight requests have the same sector (e.g., concurrent reads of the same block), the second request's start timestamp overwrites the first, causing the first completion to be missed. This is the same limitation as bpftrace's `biolatency.bt`. The bcc tool uses the request pointer (via kprobe) for more reliable keying, but tracepoint-based keying by sector is sufficient for typical workloads.
- **dd workload**: the verification uses `dd oflag=direct` instead of `fio` because `fio` with `ioengine=libaio` on this VM's virtio disk did not generate block IO tracepoint events. The `dd` approach generates consistent tracepoint events.
- **bcc biolatency requires `-d vda`**: without a device filter, bcc's `biolatency-bpfcc` hangs during `BPF.get_kprobe_functions()` on kernel 6.12 (a known BCC issue). The `-d vda` flag narrows the probe and avoids the slow function enumeration.
- **No interval mode**: the tool does not support periodic histogram printing (interval mode). This is a minor feature gap; the duration mode (`-d N`) is sufficient for M2 verification.
- **Single CPU system**: with 2 vCPUs, the block IO tracepoints fire on whichever CPU the IO completion interrupt arrives on. The BPF program is per-CPU safe (uses `bpf_map_update_elem` with `BPF_ANY`).
