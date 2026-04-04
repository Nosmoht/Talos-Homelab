---
name: linstor-storage-triage
description: "Triage LINSTOR/DRBD storage health: degraded resources, satellite status, sole-replica safety check before node drain, and HA controller behavior."
argument-hint: "[--node <node-name>] [--resource <pvc-name>]"
disable-model-invocation: true
allowed-tools: Bash, Read, Write
---

# LINSTOR Storage Triage

## Environment Setup

Read `.claude/environment.yaml` for kubeconfig path and node IP map.
If the file is missing, stop: "Copy `.claude/environment.example.yaml` to `.claude/environment.yaml` and fill in your cluster details."

## Reference Files

Read before acting:
- `docs/day2-operations.md` — LINSTOR health commands, DRBD D-state troubleshooting, storage pool thresholds
- `.claude/rules/talos-operations.md` — "DRBD volumes in D-state deadlock upgrade" gotcha — critical reading before any node operation

## Inputs

- `--node <name>`: If specified, run pre-drain sole-replica safety check for this node.
- `--resource <pvc-name>`: If specified, focus on a single LINSTOR resource by PVC name.

## Scope Guard

If a node drain is blocked by this triage:
- Run this skill FIRST to diagnose the blocking resources
- Then use `/talos-apply` or `/talos-upgrade` for the node operation itself

If the issue is an ArgoCD sync failure for the Piraeus operator:
- Suggest `/gitops-health-triage` instead

## Workflow

### 1. Node health

Run:
```bash
KUBECONFIG=<kubeconfig> kubectl linstor node list
```

Flag any satellite OFFLINE or UNKNOWN as **CRIT** — stop and report:
> "Satellite <name> is OFFLINE. DRBD cannot replicate. Resolve this before any node operations. Check `docs/day2-operations.md` LINSTOR section."

### 2. Storage pool saturation

Run:
```bash
KUBECONFIG=<kubeconfig> kubectl linstor storage-pool list
```

Flag pools below 20% free as **WARN**. Flag pools below 5% free as **CRIT**.

### 3. Degraded resources

Run:
```bash
KUBECONFIG=<kubeconfig> kubectl linstor resource list
```

If `--resource` specified, filter output to that resource.

Identify resources where replica count < configured count (typically 2 or 3).
Flag Degraded/SyncTarget/Inconsistent state as **WARN**.
Flag multiple simultaneous degraded resources as **CRIT** — data loss risk.

### 4. HA controller status

Run:
```bash
KUBECONFIG=<kubeconfig> kubectl -n piraeus-datastore get pods -l app.kubernetes.io/name=piraeus-ha-controller
KUBECONFIG=<kubeconfig> kubectl -n piraeus-datastore logs -l app.kubernetes.io/name=piraeus-ha-controller --tail=50
```

Look for quorum loss events, pod eviction actions, or repeated restarts.

### 5. Pre-drain sole-replica check (only when --node specified)

Cross-reference `kubectl linstor resource list` with the target node.

For each DRBD resource on the target node:
- Count how many OTHER nodes have an UpToDate replica
- If any resource has 0 other UpToDate replicas, BLOCK and report:
  > "Node <name> cannot be safely drained — DRBD resource <X> has no other live replica.
  > Add a replica on another node before draining:
  > `kubectl linstor resource create <X> <other-node>`"

Do not proceed with node drain guidance if this check fails.

### 6. Post-maintenance sync verification (only when --node specified, after drain)

After the node returns from maintenance:
```bash
KUBECONFIG=<kubeconfig> kubectl linstor resource list
```

Confirm all resources on the returning node reach UpToDate state.
If sync takes >5 minutes, flag as **WARN** and suggest checking `docs/day2-operations.md`.

## Output

Present a storage health report:

```
| Check              | Status      | Details |
|--------------------|-------------|---------|
| Satellites         | OK/CRIT     | N online |
| Pool saturation    | OK/WARN/CRIT| pools below threshold |
| Resource health    | OK/WARN/CRIT| N degraded |
| HA controller      | OK/WARN     | events summary |
| Pre-drain check    | PASS/BLOCK  | resources at risk |
```

If the pre-drain check blocks, output a clear summary listing each blocking resource and the exact command to add a replica.

## Hard Rules

- Read-only: this skill observes storage state, never modifies it.
- If the sole-replica check fails, the node operation MUST be blocked — no override.
- DRBD D-state (as documented in `.claude/rules/talos-operations.md`) requires power-cycle recovery — never attempt to proceed through it.
