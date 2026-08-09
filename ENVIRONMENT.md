# ENVIRONMENT.md — Target Environment Probe Results (Populated During M0)

> This file is probed and populated by the agent during the M0 phase. It serves as the basis for all subsequent technology choices.
> Each item includes the probe command and the measured value. Speculative values are forbidden; items that cannot be probed are marked `N/A` with an explanation.

## PC

| Item | Probe Command | Measured Value |
|------|---------------|----------------|
| Kernel version | `uname -r` | TBD |
| Distribution | `cat /etc/os-release` | TBD |
| BTF available | `ls /sys/kernel/btf/vmlinux` | TBD |
| `CONFIG_BPF*` | `grep -E 'CONFIG_(BPF|BPF_SYSCALL|BPF_JIT|DEBUG_INFO_BTF)' /boot/config-$(uname -r)` | TBD |
| CPU model | `lscpu` | TBD |
| Memory | `free -h` | TBD |
| Disk model | `lsblk -d -o NAME,MODEL,SIZE` / `nvme list` | TBD |
| GPU model | `nvidia-smi -L` | TBD |
| Container runtime | `docker --version` | TBD |

## TrueNAS SCALE

| Item | Probe Command | Measured Value |
|------|---------------|----------------|
| Kernel version | `uname -r` | TBD |
| BTF available | `ls /sys/kernel/btf/vmlinux` | TBD |
| Disk configuration | `zpool status` | TBD |
| Container runtime | (Record per SCALE's actual form) | TBD |

## Probe Conclusions

(To be populated during M0: eBPF feasibility conclusion, monitoring stack deployment form, technology selection impacts to be recorded in DECISIONS.md.)
