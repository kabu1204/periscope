# Design Note: M0 — Environment Probing + Monitoring Stack Deployment

## Conclusion First

M0 is complete. The PC environment was probed and `ENVIRONMENT.md` is fully populated with no `TBD` placeholders. A containerized monitoring stack (Prometheus, Grafana, node_exporter) was deployed using podman-compose with host networking. An initial Grafana dashboard ("Periscope M0 — System Overview") displays CPU usage, memory, disk I/O, network I/O, and uptime on a unified 10-second-refresh timeline. All four `ci_report.sh` M0 checks pass.

## Background and Principles

### Environment Probing

Before selecting eBPF tooling or deploying monitoring, the host kernel must be validated for BPF support. Three kernel facilities matter:

- **BPF system call** (`CONFIG_BPF_SYSCALL`): enables userspace to load BPF programs into the kernel.
- **BPF JIT** (`CONFIG_BPF_JIT`): compiles BPF bytecode to native machine code for in-kernel execution performance.
- **BTF** (`CONFIG_DEBUG_INFO_BTF`): exposes the kernel's type information at `/sys/kernel/btf/vmlinux`, allowing CO-RE (Compile Once – Run Everywhere) programs that adapt to different kernel versions without recompilation.

All three were confirmed present on this host (kernel 6.12.95, Debian 13 trixie).

### Monitoring Stack Architecture

The monitoring stack follows a standard pull-based metrics pipeline:

1. **node_exporter** — runs on the host (in a container with host PID namespace and read-only `/proc`, `/sys` mounts), exposes hardware and OS metrics at `:9100/metrics` in Prometheus exposition format.
2. **Prometheus** — scrapes node_exporter every 15 seconds, stores time-series data in its TSDB.
3. **Grafana** — queries Prometheus via its HTTP API and renders dashboards.

All three run as containers. Grafana datasource and dashboard provisioning are configured via declarative YAML/JSON files checked into the repository, so the dashboard appears automatically on startup without manual UI configuration.

## Design

### Container Runtime: podman (D-002)

Docker was initially considered (and partially installed), but the user requested podman for its daemonless, lightweight nature. podman-compose is compatible with `docker-compose.yml` syntax. See `DECISIONS.md` D-002.

### Network Mode: host

The initial deployment used podman's default bridge network. While DNS resolution between containers worked (verified with `nslookup` from the Prometheus container), HTTP connections between containers timed out due to residual Docker iptables rules in the `FORWARD` chain blocking bridge traffic. Rather than modifying host firewall rules (forbidden per `AGENTS.md` — "modifying host system configuration is forbidden"), all three services were switched to `network_mode: host`. This means each container binds directly to host ports (9090, 9100, 3000), and Prometheus scrapes `localhost:9100` instead of `node_exporter:9100`.

### Dashboard

The dashboard (`monitoring/grafana/dashboards/m0-overview.json`) is provisioned automatically via Grafana's file-based provisioning system. It contains:

- **CPU Usage (%)**: `100 - avg(rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100`, stacked by instance.
- **Memory**: `MemTotal - MemAvailable` (used) and `MemAvailable`, stacked.
- **Disk I/O (bytes/s)**: `rate(node_disk_read_bytes_total[1m])` and `rate(node_disk_written_bytes_total[1m])`, stacked by device.
- **Network I/O (bytes/s)**: `rate(node_network_receive_bytes_total[1m])` and `rate(node_network_transmit_bytes_total[1m])`, stacked by device.
- **Uptime**: `time() - node_boot_time_seconds`, displayed as a stat panel.

All panels share the same time range (default: last 1 hour, auto-refresh 10s), providing the unified timeline required by G1.

### Components Not Deployed

- **DCGM exporter**: not deployed (no NVIDIA GPU detected).
- **nvme/smartctl exporter**: not deployed (no NVMe device; the only disk is a virtio virtual disk).
- **TrueNAS monitoring**: deferred — the TrueNAS SCALE machine is not accessible from this environment.

## Verification

**Oracle**: Health-check endpoints (per `ROADMAP.md` M0 acceptance criteria).

| Check | Method | Result |
|-------|--------|--------|
| ENVIRONMENT.md has no TBD | `! grep -q TBD ENVIRONMENT.md` | PASS |
| Prometheus healthy | `curl -sf http://localhost:9090/-/healthy` | PASS |
| Grafana healthy | `curl -sf http://localhost:3000/api/health` | PASS |
| node_exporter up | `curl -sf http://localhost:9100/metrics` | PASS |
| Prometheus scraping node_exporter | `curl /api/v1/targets` → both targets `health=up` | PASS |
| Grafana dashboard provisioned | `curl -u admin:admin /api/search?type=dash-db` → dashboard found | PASS |
| Metrics data flowing | `curl /api/v1/query?query=node_cpu_seconds_total` → 16 series returned | PASS |

`ci_report.sh m0` output: `pass: 4  fail: 0`

## How to Manually Verify

1. **Start the stack** (if not already running):
   ```bash
   cd monitoring && podman-compose -f docker-compose.yml up -d
   ```

2. **Check service health**:
   ```bash
   curl -sf http://localhost:9090/-/healthy    # → "Prometheus Server is Healthy."
   curl -sf http://localhost:9100/metrics      # → metrics in text exposition format
   curl -sf http://localhost:3000/api/health   # → JSON with "database":"ok"
   ```

3. **Check Prometheus targets**:
   ```bash
   curl -sf http://localhost:9090/api/v1/targets | python3 -m json.tool
   # Both "prometheus" and "node_exporter" jobs should show "health": "up"
   ```

4. **Open Grafana in a browser**:
   - URL: `http://<host-ip>:3000`
   - Login: admin / admin
   - Navigate to Dashboards → "Periscope M0 — System Overview"
   - Verify that CPU, memory, disk, and network panels show live data.

5. **Run the CI check**:
   ```bash
   ./ci_report.sh m0
   # Expected: pass: 4  fail: 0
   ```

## Known Limitations

- **Host networking**: using `network_mode: host` means all three services bind to host ports directly. Port conflicts are possible if other services on the host use ports 9090, 9100, or 3000.
- **No persistent storage retention policy**: Prometheus uses default retention (15 days). Long-term storage is not configured (out of scope for M0).
- **No GPU metrics**: the host has no NVIDIA GPU. If a GPU is added later, DCGM exporter should be included.
- **No NVMe/SMART metrics**: the host's only disk is a virtio virtual disk. On a physical machine with NVMe, the smartctl exporter should be added.
- **TrueNAS not monitored**: the TrueNAS SCALE machine was not accessible during M0. Monitoring for that host should be added as a follow-up.
- **Single host only**: the stack monitors only the PC. No remote scraping or federation is configured.
