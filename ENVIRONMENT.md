# ENVIRONMENT.md — Target Environment Probe Results (Populated During M0)

> This file is probed and populated by the agent during the M0 phase. It serves as the basis for all subsequent technology choices.
> Each item includes the probe command and the measured value. Speculative values are forbidden; items that cannot be probed are marked `N/A` with an explanation.

## PC

| Item | Probe Command | Measured Value |
|------|---------------|----------------|
| Kernel version | `uname -r` | 6.12.95+deb13-amd64 |
| Distribution | `cat /etc/os-release` | Debian GNU/Linux 13 (trixie) |
| BTF available | `ls /sys/kernel/btf/vmlinux` | Yes — `/sys/kernel/btf/vmlinux` present (4,961,207 bytes) |
| `CONFIG_BPF*` | `grep -E 'CONFIG_(BPF\|BPF_SYSCALL\|BPF_JIT\|DEBUG_INFO_BTF)' /boot/config-$(uname -r)` | `CONFIG_BPF=y`, `CONFIG_BPF_SYSCALL=y`, `CONFIG_BPF_JIT=y`, `CONFIG_BPF_JIT_DEFAULT_ON=y`, `CONFIG_BPF_LSM=y`, `CONFIG_BPF_STREAM_PARSER=y`, `CONFIG_BPF_EVENTS=y`, `CONFIG_DEBUG_INFO_BTF=y`, `CONFIG_DEBUG_INFO_BTF_MODULES=y` |
| CPU model | `lscpu` | AMD EPYC 7K62 48-Core Processor (2 vCPUs, KVM virtualized, 1 thread/core) |
| Memory | `free -h` | 1.9 GiB total |
| Disk model | `lsblk -d -o NAME,MODEL,SIZE` / `nvme list` | `vda` — 40 GB virtio virtual disk (no NVMe; `nvme` tool not installed) |
| GPU model | `nvidia-smi -L` | N/A — no NVIDIA GPU (`nvidia-smi` not found) |
| Container runtime | `podman --version` | podman 5.4.2 + podman-compose 1.3.0 (user preference; see DECISIONS.md D-002) |

## TrueNAS SCALE

| Item | Probe Command | Measured Value |
|------|---------------|----------------|
| Kernel version | `uname -r` | N/A — TrueNAS SCALE machine not accessible from this environment |
| BTF available | `ls /sys/kernel/btf/vmlinux` | N/A — TrueNAS SCALE machine not accessible from this environment |
| Disk configuration | `zpool status` | N/A — TrueNAS SCALE machine not accessible from this environment |
| Container runtime | (Record per SCALE's actual form) | N/A — TrueNAS SCALE machine not accessible from this environment |

> **Note**: The TrueNAS SCALE machine could not be probed in this session. When it becomes accessible, re-run the probe commands and update this section. M0 monitoring stack deployment is scoped to the PC only for now; TrueNAS monitoring can be added as a follow-up once the machine is reachable.

## Probe Conclusions

### eBPF Feasibility

The PC kernel (6.12.95, Debian 13 trixie) fully supports modern eBPF development:

- **BTF**: Available (`CONFIG_DEBUG_INFO_BTF=y`), enabling CO-RE (Compile Once – Run Everywhere) and `bpftool btf dump` workflows. This means libbpf-rs and aya are both viable; the selection is deferred to M2 (D-001).
- **BPF syscall and JIT**: Both enabled (`CONFIG_BPF_SYSCALL=y`, `CONFIG_BPF_JIT=y`, `CONFIG_BPF_JIT_DEFAULT_ON=y`).
- **BPF LSM and stream parser**: Available, but not required for the M2/M3 tools (latency histograms and off-CPU attribution).
- **Kernel version 6.12**: Recent enough for all planned probe types (kprobe, tracepoint, uprobe). `sched_switch` tracepoint, block IO tracepoints, and `finish_task_switch` are all available.

**Conclusion**: eBPF tool development (M2, M3) is feasible on this kernel. No kernel module installation is needed.

### Monitoring Stack Deployment Form

- Container runtime: **podman** + **podman-compose** (user preference, lightweight alternative to Docker).
- Stack components: Prometheus, Grafana, node_exporter. No DCGM exporter (no GPU). No nvme/smartctl exporter (no NVMe; the only disk is a virtio virtual disk).
- Deployment scoped to the PC; TrueNAS monitoring deferred until that machine is accessible.

### Technology Selection Impacts (to be recorded in DECISIONS.md)

- **D-001 (eBPF library)**: Both libbpf-rs and aya are viable given BTF availability. Final selection deferred to M2.0.
- **D-002 (container runtime)**: podman chosen over Docker per user preference. Recorded in DECISIONS.md.
