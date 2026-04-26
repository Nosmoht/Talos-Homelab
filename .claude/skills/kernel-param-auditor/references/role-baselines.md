# Kernel Parameter Role Baselines

Per-role expected sysctl values consumed by `kernel-param-auditor`. The SKILL parses the **Baseline Table** below at runtime: rows define expected values per parameter for each node-role (`cp`, `worker`, `storage`, `gpu`). Rows in the **Severity Table** classify drift as `WARNING` or `CRITICAL`.

Baselines are starting values from public Linux tuning guidance, Talos defaults, and Kubernetes performance literature. Tune in this file's git history; do not silently mutate.

## Roles

| Role | Detection rule (in priority order) |
|---|---|
| `cp` | Node has label `node-role.kubernetes.io/control-plane` (value `""` or `"true"`) |
| `storage` | Node has label `feature.node.kubernetes.io/storage-nvme.present=true` AND not `cp` |
| `gpu` | Node name contains `gpu` OR has label `node.kubernetes.io/gpu` AND not `cp`/`storage` |
| `worker` | Default fallback for any node not matching above |

A node may match `cp` and one of `storage`/`gpu` simultaneously. Precedence is `cp > storage > gpu > worker` — control-plane responsibilities dominate.

## Baseline Table

`expected` is the value `kernel-param-auditor` will compare `talos_read_file /proc/sys/<param>` against. `*` means "any value, do not flag" (parameter probed for evidence but no drift verdict). Empty cell means "not in scope for this role" — the SKILL skips the read.

| Parameter (path under `/proc/sys/`) | cp | worker | storage | gpu | Category |
|---|---|---|---|---|---|
| `net/core/rmem_max` | `16777216` | `16777216` | `33554432` | `16777216` | net |
| `net/core/wmem_max` | `16777216` | `16777216` | `33554432` | `16777216` | net |
| `net/core/rmem_default` | `262144` | `262144` | `1048576` | `262144` | net |
| `net/core/wmem_default` | `262144` | `262144` | `1048576` | `262144` | net |
| `net/core/netdev_max_backlog` | `16384` | `16384` | `30000` | `16384` | net |
| `net/core/somaxconn` | `4096` | `4096` | `4096` | `4096` | net |
| `net/ipv4/tcp_rmem` | `4096 87380 16777216` | `4096 87380 16777216` | `4096 131072 33554432` | `4096 87380 16777216` | net |
| `net/ipv4/tcp_wmem` | `4096 65536 16777216` | `4096 65536 16777216` | `4096 131072 33554432` | `4096 65536 16777216` | net |
| `net/ipv4/tcp_congestion_control` | `bbr` | `bbr` | `bbr` | `bbr` | net |
| `net/ipv4/tcp_mtu_probing` | `1` | `1` | `1` | `1` | net |
| `net/ipv4/tcp_slow_start_after_idle` | `0` | `0` | `0` | `0` | net |
| `net/ipv4/ip_forward` | `1` | `1` | `1` | `1` | net |
| `net/bridge/bridge-nf-call-iptables` | `1` | `1` | `1` | `1` | net |
| `vm/swappiness` | `0` | `0` | `0` | `0` | vm |
| `vm/overcommit_memory` | `1` | `1` | `1` | `1` | vm |
| `vm/max_map_count` | `262144` | `262144` | `1048576` | `262144` | vm |
| `vm/dirty_ratio` | `20` | `20` | `10` | `20` | vm |
| `vm/dirty_background_ratio` | `10` | `10` | `5` | `10` | vm |
| `fs/file-max` | `*` | `*` | `*` | `*` | fs |
| `fs/inotify/max_user_instances` | `8192` | `8192` | `8192` | `8192` | fs |
| `fs/inotify/max_user_watches` | `524288` | `524288` | `524288` | `524288` | fs |
| `kernel/pid_max` | `4194304` | `4194304` | `4194304` | `4194304` | kernel |
| `kernel/panic` | `10` | `10` | `10` | `10` | kernel |
| `kernel/panic_on_oops` | `1` | `1` | `1` | `1` | kernel |
| `kernel/kptr_restrict` | `1` | `1` | `1` | `1` | kernel |

### Parameter Selection Rationale

- **net.core.rmem_max / wmem_max / rmem_default / wmem_default** — TCP socket buffer caps. Storage tier doubles to 32 MiB to absorb DRBD replication burst traffic.
- **net.core.netdev_max_backlog** — RX queue depth before drops; storage tier raised to 30000 for replication throughput.
- **net.core.somaxconn** — listen backlog; sized for kube-apiserver and ingress fan-out.
- **net.ipv4.tcp_rmem / tcp_wmem** — per-socket dynamic window range; storage tier widens for long-fat pipes.
- **net.ipv4.tcp_congestion_control** — `bbr` recommended on Talos; flag drift to `cubic` or `reno`.
- **net.ipv4.tcp_mtu_probing** — required for mixed-MTU paths (WireGuard / VXLAN) without PMTUD black holes.
- **net.ipv4.tcp_slow_start_after_idle** — disable to avoid throughput collapse after idle on persistent control-plane / replication connections.
- **net.ipv4.ip_forward / net.bridge.bridge-nf-call-iptables** — required for Kubernetes networking; CRITICAL if missing on any role.
- **vm.swappiness** — Kubernetes/Talos require `0` (no swap); CRITICAL on storage and cp.
- **vm.overcommit_memory** — `1` (always overcommit) avoids OOM during fork-heavy workloads.
- **vm.max_map_count** — bumped on storage for processes with many DRBD/loop devices and memory-mapped files.
- **vm.dirty_ratio / vm.dirty_background_ratio** — storage tier lowered to flush sooner under DRBD replication.
- **fs.file-max** — discovered & reported as evidence; expected scales with RAM and is not a fixed target.
- **fs.inotify.max_user_instances / max_user_watches** — Argo CD, kubelet, and operators all consume inotify; raise above kernel default.
- **kernel.pid_max** — required for high pod density (Talos kubelet `--max-pods`).
- **kernel.panic / panic_on_oops** — auto-reboot on panic so HA sweeps the failed node out within `kernel.panic` seconds.
- **kernel.kptr_restrict** — hide kernel pointers from non-root for kASLR effectiveness.

Total: 25 parameters spanning net (13), vm (5), fs (3), kernel (4).

## Severity Table

Drift severity per parameter. The SKILL applies these rules to compute interface verdict; node verdict is the worst per-parameter verdict.

| Parameter | Default severity | CRITICAL on roles | Notes |
|---|---|---|---|
| `net/core/rmem_max` | WARNING | `cp`, `storage` | Storage replication & API control plane |
| `net/core/wmem_max` | WARNING | `cp`, `storage` | Same |
| `net/core/rmem_default` | WARNING | — | |
| `net/core/wmem_default` | WARNING | — | |
| `net/core/netdev_max_backlog` | WARNING | `storage` | RX drops cause DRBD resync loops |
| `net/core/somaxconn` | WARNING | `cp` | Kube-apiserver listen backlog |
| `net/ipv4/tcp_rmem` | WARNING | `cp`, `storage` | net.ipv4.tcp_* on cp/storage = CRITICAL per Issue AC |
| `net/ipv4/tcp_wmem` | WARNING | `cp`, `storage` | Same |
| `net/ipv4/tcp_congestion_control` | WARNING | `cp`, `storage` | Drift from `bbr` regresses throughput |
| `net/ipv4/tcp_mtu_probing` | WARNING | `cp`, `storage` | PMTUD black hole risk on WireGuard |
| `net/ipv4/tcp_slow_start_after_idle` | WARNING | `cp`, `storage` | |
| `net/ipv4/ip_forward` | CRITICAL | all | Kubernetes networking requirement |
| `net/bridge/bridge-nf-call-iptables` | CRITICAL | all | NetworkPolicy enforcement requirement |
| `vm/swappiness` | WARNING | `cp`, `storage` | CRITICAL on storage/cp per Issue AC |
| `vm/overcommit_memory` | WARNING | — | |
| `vm/max_map_count` | WARNING | `storage` | DRBD/loop devices |
| `vm/dirty_ratio` | WARNING | `storage` | |
| `vm/dirty_background_ratio` | WARNING | `storage` | |
| `fs/file-max` | INFO (no verdict) | — | Reported only |
| `fs/inotify/max_user_instances` | WARNING | — | |
| `fs/inotify/max_user_watches` | WARNING | — | |
| `kernel/pid_max` | WARNING | — | |
| `kernel/panic` | WARNING | — | |
| `kernel/panic_on_oops` | WARNING | — | |
| `kernel/kptr_restrict` | WARNING | — | Security hardening |

### Severity Rules (applied by SKILL)

1. If `expected` is `*` → status `INFO` regardless of actual value; never raises verdict.
2. Else if `actual == expected` (string-equal after trim) → status `OK`.
3. Else if param's `CRITICAL on roles` includes the node's role → status `CRITICAL`.
4. Else → status `WARNING`.
5. Per-node verdict precedence: `CRITICAL > WARNING > HEALTHY`. `INFO` and `OK` collapse to `HEALTHY`.

### Comparison Notes

- `tcp_rmem` / `tcp_wmem` are tuples (`min default max`). Compare after collapsing whitespace to single spaces and trimming. Drift in any of the three tuple values triggers the rule.
- All other values are scalar. Compare as trimmed strings — kernel exposes integers as text in `/proc/sys/`.
- Absent file (read returns precondition error) → record `actual: null`, status `PRECONDITION_NOT_MET`, do not raise the node-level verdict (already handled by per-node `PRECONDITION_NOT_MET`).

## Tuning Workflow

1. Run `/kernel-param-auditor --save-baseline` after a clean post-upgrade reconciliation.
2. If a parameter consistently fires WARNING on a healthy cluster, update the role column and document the change in this file's git history with rationale.
3. Never silently lower CRITICAL thresholds — escalate via the team-red review process for any change touching `tcp_*`, `vm/swappiness`, or `ip_forward`.
