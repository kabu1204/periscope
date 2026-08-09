// SPDX-License-Identifier: GPL-2.0
// offcpu.bpf.c — Off-CPU time attribution by stack, BPF program
//
// Measures how long tasks spend off-CPU (blocked) and attributes that
// time to the task's kernel + user stack captured when it was scheduled
// out. Equivalent to bcc offcputime.

#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>

// Maximum number of distinct stacks aggregated simultaneously.
#define MAX_ENTRIES 10000

// Maximum stack depth captured (kernel and user each).
// Must not exceed the kernel's perf_event_max_stack (127 on this machine).
#define MAX_STACK_DEPTH 127

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

// Aggregation key: one blocked task's identity plus its stacks.
struct key_t {
    u32 pid;                  // thread id (tgid in userspace terms)
    u64 kernel_stack_id;      // stack id from stackmap, or -errno
    u64 user_stack_id;        // stack id from stackmap, or -errno
    char comm[16];            // task name at schedule-out time
};

// Hash map: task pid -> timestamp (ns) when it was scheduled out.
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, MAX_ENTRIES);
    __type(key, u32);   // task pid
    __type(value, u64); // schedule-out timestamp in nanoseconds
} start SEC(".maps");

// Hash map: aggregation key -> total off-CPU time in microseconds.
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, MAX_ENTRIES);
    __type(key, struct key_t);
    __type(value, u64); // total off-CPU microseconds
} counts SEC(".maps");

// Stack trace map shared by kernel and user stack captures.
struct {
    __uint(type, BPF_MAP_TYPE_STACK_TRACE);
    __uint(max_entries, MAX_ENTRIES);
    __type(key, u32);            // stack id
    __type(value, u64[MAX_STACK_DEPTH]); // instruction pointers
} stackmap SEC(".maps");

// tracepoint:sched:sched_switch
//
// On schedule-out of prev: record the timestamp keyed by prev's pid.
// On schedule-in of next: compute how long next was off-CPU, capture its
// kernel and user stacks (taken from this CPU's context, which is now
// running next), and accumulate the delta under that stack key.
SEC("tracepoint/sched/sched_switch")
int trace_sched_switch(struct sched_switch_ctx *ctx) {
    u64 ts = bpf_ktime_get_ns();

    u32 prev_pid = (u32)ctx->prev_pid;
    u32 next_pid = (u32)ctx->next_pid;

    // Skip the idle task entirely: its off-CPU time is idle time, not
    // blocking, and bcc offcputime excludes it.
    if (prev_pid == 0 || next_pid == 0)
        return 0;

    // Record when prev goes off-CPU.
    bpf_map_update_elem(&start, &prev_pid, &ts, BPF_ANY);
    u64 *tsp = bpf_map_lookup_elem(&start, &next_pid);
    if (!tsp)
        return 0;
    u64 delta = ts - *tsp;
    bpf_map_delete_elem(&start, &next_pid);

    // next_pid == bpf_get_current_pid_tgid()'s thread id at this point:
    // this tracepoint fires in the context of the task being switched in.
    struct key_t key = {};
    key.pid = next_pid;
    bpf_get_current_comm(&key.comm, sizeof(key.comm));

    // Capture stacks. Errors are recorded as negative ids (as u64),
    // matching bcc's convention.
    long ksid = bpf_get_stackid(ctx, &stackmap, 0);
    key.kernel_stack_id = (u64)ksid;
    long usid = bpf_get_stackid(ctx, &stackmap, BPF_F_USER_STACK);
    key.user_stack_id = (u64)usid;

    // Convert to microseconds for the report.
    u64 delta_us = delta / 1000;

    u64 *cnt = bpf_map_lookup_elem(&counts, &key);
    if (cnt) {
        (*cnt) += delta_us;
    } else {
        bpf_map_update_elem(&counts, &key, &delta_us, BPF_ANY);
    }

    return 0;
}

char LICENSE[] SEC("license") = "GPL";
