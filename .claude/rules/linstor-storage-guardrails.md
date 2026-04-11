---
paths:
  - "kubernetes/**/piraeus-operator/**"
  - "kubernetes/base/**/piraeus-operator/**"
  - "docs/day2-operations.md"
---

# LINSTOR / DRBD Storage Guardrails

## Architecture

```
Piraeus Operator (Helm, piraeus-datastore namespace)
  └── LINSTOR Controller (stateful, API server)
       └── LINSTOR Satellites (DaemonSet, one per storage node)
            └── DRBD kernel module (loaded natively by Talos)
                 └── LVM volume group "linstor" on /dev/nvme0n1
```

- Satellites run as privileged pods with host `/dev` access
- LINSTOR CLI: `kubectl linstor` plugin or `kubectl exec` into controller pod
- CSI driver promotes DRBD to Primary before mount, demotes after unmount
- Storage nodes: nodes with `feature.node.kubernetes.io/storage-nvme.present=true`

## StorageClasses

| Class | Replicas | FS | Use for |
|-------|----------|----|---------|
| `linstor-csi` (default) | 2 | XFS | General workloads |
| `linstor-nvme-noreplica` | 1 | XFS | Non-critical, single-replica |
| `linstor-vm` | 2 | raw block | KubeVirt VMs |

## Known Failure Modes

**XFS superblock corruption** (most common): Unclean DRBD demotion (node crash, power loss) corrupts XFS metadata. Symptom: mount exit code 32, "bad superblock" in CSI logs, pod stuck in ContainerCreating with a looping promote/demote cycle. Fix: `/linstor-volume-repair`.

**DRBD D-state deadlock**: DRBD volumes in D-state block node shutdown. DRBD processes enter an uninterruptible sleep waiting for I/O that never completes. Only fixable with physical power cycle. See `talos-mcp-first.md` §Node Recovery. Do not attempt `kubectl drain`, `talosctl upgrade`, or satellite pod restart to resolve D-state.

**Split-brain**: Two nodes both promoted to Primary simultaneously (typically after network partition + manual intervention). LINSTOR/DRBD auto-resolution is configured, but if manual promotion occurred, one replica will have diverged data. Do not continue mounting until split-brain is resolved.

## Safety Constraints

- Never delete a LINSTOR resource to fix corruption — this destroys all replica data permanently.
- Never run `mkfs` on a DRBD device that may contain data. Use `xfs_repair` for XFS corruption.
- Never resize a LINSTOR volume while DRBD is in a degraded state.
- Never change StorageClass replica count on existing PVCs.
- Never promote DRBD manually on a node where the satellite pod is not Running.
- Talos nodes have no host shell — all device-level operations must go through satellite pod exec.
- Satellite exec for device ops: `kubectl exec -n piraeus-datastore <satellite-pod> -- <command>`

## Access Patterns

```bash
# List nodes
kubectl linstor node list

# List resource replicas and their states
kubectl linstor resource list [-r <resource-name>]

# List volumes (shows DRBD minor number)
kubectl linstor volume list [-r <resource-name>]

# Storage pool capacity
kubectl linstor storage-pool list

# Find satellite pod on a specific node
kubectl -n piraeus-datastore get pods \
  -l app.kubernetes.io/component=linstor-satellite \
  --field-selector spec.nodeName=<node>

# Exec into satellite for device-level operations
kubectl exec -n piraeus-datastore <satellite-pod> -- <command>
```
