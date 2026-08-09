// SPDX-License-Identifier: GPL-2.0
// biolat.bpf.c — Block IO latency histogram BPF program
//
// Attaches to block:block_io_start and block:block_io_done tracepoints
// to measure the time from IO start to completion.

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

// Maximum number of in-flight IO requests tracked simultaneously.
#define MAX_ENTRIES 10000

// Number of histogram buckets (log2). Covers 0 to ~2^26 microseconds (~67s).
#define NR_BUCKETS 27

// Tracepoint context structures. These match the kernel's tracepoint format
// for block_io_start and block_io_done. We define them manually because the
// kernel exposes them via __tracepoint_block_io_start/done which use a
// generic format not captured as a named struct in vmlinux.h.
struct block_io_trace_ctx {
    unsigned short common_type;       // offset 0
    unsigned char common_flags;       // offset 2
    unsigned char common_preempt_count; // offset 3
    int common_pid;                   // offset 4
    dev_t dev;                         // offset 8
    sector_t sector;                   // offset 16
};

// Hash map: key = sector number, value = start timestamp (ns).
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, MAX_ENTRIES);
    __type(key, u64);   // sector number
    __type(value, u64); // start timestamp in nanoseconds
} start SEC(".maps");

// Array map: log2 latency histogram in microseconds.
// Index 0 = 0us, Index N = 2^(N-1) to 2^N - 1 us.
struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __uint(max_entries, NR_BUCKETS);
    __type(key, u32);   // bucket index
    __type(value, u64); // count
} hist_map SEC(".maps");

// Single-slot array map: total observed latency in microseconds (slot 0) and
// total event count (slot 1). Used to render Prometheus histogram _sum/_count.
struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __uint(max_entries, 2);
    __type(key, u32);
    __type(value, u64);
} hist_sum SEC(".maps");

// Log2 helper: returns the bucket index for a given value.
// Index 0 = 0, Index 1 = 1, Index N = 2^(N-1) to 2^N - 1.
static __always_inline int log2_bucket(u64 v) {
    if (v == 0)
        return 0;
    int floor_log2 = 63 - __builtin_clzll(v);
    int bucket = floor_log2 + 1;
    if (bucket >= NR_BUCKETS)
        bucket = NR_BUCKETS - 1;
    return bucket;
}

// tracepoint:block:block_io_start
// Records the start timestamp keyed by sector number.
SEC("tracepoint/block/block_io_start")
int trace_block_io_start(struct block_io_trace_ctx *ctx) {
    u64 ts = bpf_ktime_get_ns();
    u64 key = (u64)ctx->sector;
    bpf_map_update_elem(&start, &key, &ts, BPF_ANY);
    return 0;
}

// tracepoint:block:block_io_done
// Computes the latency and increments the histogram bucket.
SEC("tracepoint/block/block_io_done")
int trace_block_io_done(struct block_io_trace_ctx *ctx) {
    u64 *tsp;
    u64 key = (u64)ctx->sector;

    tsp = bpf_map_lookup_elem(&start, &key);
    if (!tsp)
        return 0;

    u64 delta = bpf_ktime_get_ns() - *tsp;
    bpf_map_delete_elem(&start, &key);

    // Convert to microseconds for the histogram.
    u64 delta_us = delta / 1000;

    int bucket = log2_bucket(delta_us);
    u32 bkt_key = (u32)bucket;
    u64 *cnt = bpf_map_lookup_elem(&hist_map, &bkt_key);
    if (cnt) {
        (*cnt)++;
    } else {
        u64 init = 1;
        bpf_map_update_elem(&hist_map, &bkt_key, &init, BPF_ANY);
    }

    // Accumulate total latency (us) and event count for Prometheus _sum/_count.
    u32 sum_key = 0;
    u64 *sum = bpf_map_lookup_elem(&hist_sum, &sum_key);
    if (sum)
        (*sum) += delta_us;
    u32 cnt_key = 1;
    u64 *tot = bpf_map_lookup_elem(&hist_sum, &cnt_key);
    if (tot)
        (*tot)++;

    return 0;
}

char LICENSE[] SEC("license") = "GPL";
