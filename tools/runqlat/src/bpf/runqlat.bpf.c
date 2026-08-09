// SPDX-License-Identifier: GPL-2.0
// runqlat.bpf.c — Run queue (scheduler) latency histogram BPF program
//
// Measures the time from when a task becomes runnable (sched_wakeup) to
// when it actually starts running on a CPU (sched_switch next task).
// Equivalent to bcc runqlat.

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

// Maximum number of runnable tasks tracked simultaneously.
#define MAX_ENTRIES 10240

// Number of histogram buckets (log2). Covers 0 to ~2^26 microseconds (~67s).
#define NR_BUCKETS 27

// Tracepoint context for sched:sched_wakeup and sched:sched_wakeup_new.
// Layout from /sys/kernel/tracing/events/sched/sched_wakeup/format:
//   common_type u16 @0, common_flags u8 @2, common_preempt_count u8 @3,
//   common_pid s32 @4, comm[16] @8, pid s32 @24, prio s32 @28, target_cpu s32 @32
struct sched_wakeup_ctx {
    unsigned short common_type;
    unsigned char common_flags;
    unsigned char common_preempt_count;
    int common_pid;
    char comm[16];
    pid_t pid;
    int prio;
    int target_cpu;
};

// Task state flag from the kernel (include/linux/sched.h).
#define TASK_RUNNING 0x00000000

// Tracepoint context for sched:sched_switch.
// Layout from /sys/kernel/tracing/events/sched/sched_switch/format:
//   prev_comm[16] @8, prev_pid s32 @24, prev_prio s32 @28, prev_state s64 @32,
//   next_comm[16] @40, next_pid s32 @56, next_prio s32 @60
struct sched_switch_ctx {
    unsigned short common_type;
    unsigned char common_flags;
    unsigned char common_preempt_count;
    int common_pid;
    char prev_comm[16];
    pid_t prev_pid;
    int prev_prio;
    long prev_state;
    char next_comm[16];
    pid_t next_pid;
    int next_prio;
};

// Hash map: key = task pid, value = timestamp (ns) when it became runnable.
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, MAX_ENTRIES);
    __type(key, u32);   // task pid
    __type(value, u64); // runnable timestamp in nanoseconds
} start SEC(".maps");

// Array map: log2 run queue latency histogram in microseconds.
// Index 0 = 0us, Index N = 2^(N-1) to 2^N - 1 us.
struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __uint(max_entries, NR_BUCKETS);
    __type(key, u32);   // bucket index
    __type(value, u64); // count
} hist_map SEC(".maps");

// Log2 helper: returns the bucket index for a given value.
// Index 0 = 0, Index N = 2^(N-1) to 2^N - 1.
static __always_inline int log2_bucket(u64 v) {
    if (v == 0)
        return 0;
    int floor_log2 = 63 - __builtin_clzll(v);
    int bucket = floor_log2 + 1;
    if (bucket >= NR_BUCKETS)
        bucket = NR_BUCKETS - 1;
    return bucket;
}

static __always_inline int trace_enqueue(u32 pid) {
    u64 ts = bpf_ktime_get_ns();
    bpf_map_update_elem(&start, &pid, &ts, BPF_ANY);
    return 0;
}

// tracepoint:sched:sched_wakeup — a sleeping task is woken and enqueued.
SEC("tracepoint/sched/sched_wakeup")
int trace_sched_wakeup(struct sched_wakeup_ctx *ctx) {
    return trace_enqueue((u32)ctx->pid);
}

// tracepoint:sched:sched_wakeup_new — a new task is enqueued for the first time.
SEC("tracepoint/sched/sched_wakeup_new")
int trace_sched_wakeup_new(struct sched_wakeup_ctx *ctx) {
    return trace_enqueue((u32)ctx->pid);
}

// tracepoint:sched:sched_switch — the CPU switches from prev to next.
// If next was waiting in the run queue, record its queuing latency.
SEC("tracepoint/sched/sched_switch")
int trace_sched_switch(struct sched_switch_ctx *ctx) {
    // If prev is still runnable (state == TASK_RUNNING), it was preempted
    // and re-enqueued: its queue wait starts now (same as bcc runqlat).
    u32 prev_pid = (u32)ctx->prev_pid;
    if (ctx->prev_state == TASK_RUNNING && prev_pid != 0) {
        u64 ts = bpf_ktime_get_ns();
        bpf_map_update_elem(&start, &prev_pid, &ts, BPF_ANY);
    }

    u32 pid = (u32)ctx->next_pid;
    u64 *tsp = bpf_map_lookup_elem(&start, &pid);
    if (!tsp)
        return 0;

    u64 delta = bpf_ktime_get_ns() - *tsp;
    bpf_map_delete_elem(&start, &pid);

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

    return 0;
}

char LICENSE[] SEC("license") = "GPL";
