---
paths:
  - "talos/nodes/**"
---

# Talos Node Configuration

## Node IP Mapping
| Node | IP | Role | NIC |
|------|-----|------|-----|
| node-01 | 192.168.2.61 | control-plane | enp0s31f6 |
| node-02 | 192.168.2.62 | control-plane | enp0s31f6 |
| node-03 | 192.168.2.63 | control-plane | enp0s31f6 |
| node-04 | 192.168.2.64 | worker | enp0s31f6 |
| node-05 | 192.168.2.65 | worker | enp0s31f6 |
| node-06 | 192.168.2.66 | worker | enp0s31f6 |
| node-gpu-01 | 192.168.2.67 | worker (GPU) | enp0s20f0u2 (USB) |

## Node File Structure
- Per-node: `talos/nodes/<name>.yaml` — hostname, static IP, install disk (by-path), VIP (CP nodes only)
- **Always use `hardwareAddr: <mac>`** in deviceSelector — `physical: true` matches ALL NICs, breaks multi-NIC nodes
- node-gpu-01 USB NIC (Realtek RTL8153) needs `siderolabs/realtek-firmware` extension; without it: 5% RX drops
- Install disks use stable `/dev/disk/by-path/` (not `/dev/sda` which shifts with USB)
- Standard nodes: `pci-0000:00:17.0-ata-1`, GPU node: `pci-0000:00:17.0-ata-3`
- VIP (`192.168.2.60`) goes in per-node patches (CP only), NOT role patches (strategic merge appends)

## Node Operations
- CiliumNode CRDs retain stale IPs after IP change — fix: `kubectl delete ciliumnode <node>` + restart Cilium pod
- Approve kubelet CSRs manually if cert-approver is on unreachable node: `kubectl certificate approve <csr>`
- Config apply changing network interfaces triggers reboot — drain DRBD volumes first
