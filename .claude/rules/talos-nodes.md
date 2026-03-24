---
paths:
  - "talos/nodes/**"
---

# Talos Node Configuration

## Node IP Mapping
Node inventory (names, IPs, roles, NICs) is defined in `.claude/environment.yaml` under `nodes`.
Read that file for the authoritative node-to-IP mapping.
The Makefile (`talos/Makefile`) also contains `IP_<node>` variables that must stay consistent.

## Node File Structure
- Per-node: `talos/nodes/<name>.yaml` — hostname, static IP, install disk (by-path), VIP (CP nodes only)
- **Always use `hardwareAddr: <mac>`** in deviceSelector — `physical: true` matches ALL NICs, breaks multi-NIC nodes
- node-gpu-01 USB NIC (Realtek RTL8153) needs `siderolabs/realtek-firmware` extension; without it: 5% RX drops
- Install disks use stable `/dev/disk/by-path/` (not `/dev/sda` which shifts with USB)
- Install disks use stable `/dev/disk/by-path/` — check per-node YAML for exact paths
- API VIP (from `cluster.api_vip` in `environment.yaml`) goes in per-node patches (CP only), NOT role patches (strategic merge appends)

## Node Operations
- CiliumNode CRDs retain stale IPs after IP change — fix: `kubectl delete ciliumnode <node>` + restart Cilium pod
- Approve kubelet CSRs manually if cert-approver is on unreachable node: `kubectl certificate approve <csr>`
- Config apply changing network interfaces triggers reboot — drain DRBD volumes first
