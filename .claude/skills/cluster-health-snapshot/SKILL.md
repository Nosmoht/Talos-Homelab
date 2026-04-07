---
name: cluster-health-snapshot
description: "Check cluster health across Talos, Kubernetes, Cilium, LINSTOR, and PKI. Use after upgrades, maintenance, or ArgoCD syncs to verify all subsystems are healthy."
argument-hint: "[--subsystem talos|k8s|cilium|storage|pki|all]"
disable-model-invocation: true
allowed-tools: Bash, Read, Write
---

# Cluster Health Snapshot

## Environment Setup

Read `.claude/environment.yaml` for kubeconfig path, CP node IPs, and full node IP map.
If the file is missing, stop: "Copy `.claude/environment.example.yaml` to `.claude/environment.yaml` and fill in your cluster details."

Extract variables before running any commands:
```bash
CP1=$(yq '.nodes.control_plane[0].ip' .claude/environment.yaml)
CP2=$(yq '.nodes.control_plane[1].ip' .claude/environment.yaml)
CP3=$(yq '.nodes.control_plane[2].ip' .claude/environment.yaml)
KUBECONFIG=$(yq '.kubeconfig' .claude/environment.yaml)
```
If any variable is empty after extraction, stop: "Required field missing in `.claude/environment.yaml`. Check `.claude/environment.example.yaml` for the schema."

## Reference Files

Read before acting:
- `.claude/environment.yaml` — kubeconfig, CP IPs, node inventory
- `docs/day2-operations.md` — "Cluster Health Checks" section (commands per subsystem, thresholds)
- `.claude/rules/talos-operations.md` — etcd quorum thresholds, D-state recovery guidance

## Inputs

- `$ARGUMENTS`: Optional `--subsystem` filter. Supported values: `talos`, `k8s`, `cilium`, `storage`, `pki`, `all`. Default: `all`.

Examples:
```
/cluster-health-snapshot
/cluster-health-snapshot --subsystem cilium
/cluster-health-snapshot --subsystem storage
```

## Scope Guard

This is a read-only health check. If remediation is needed, suggest the appropriate skill:
- ArgoCD sync failures → `/gitops-health-triage`
- Storage degraded/DRBD issues → `/linstor-storage-triage`
- XFS corruption (mount exit 32, bad superblock) → `/linstor-volume-repair` (after triage)
- Cilium policy drops → `/cilium-policy-debug`
- Node config or upgrade needed → `/talos-apply` or `/talos-upgrade`

Do not attempt remediation from this skill.

## Workflow

### 1. Talos layer (skip if --subsystem not talos/all)

Run:
```bash
talosctl -n $CP1 -e $CP1 health --control-plane-nodes $CP1,$CP2,$CP3
talosctl -n $CP1 -e $CP1 etcd members
talosctl -n $CP1 -e $CP1 etcd status
```

If `talosctl health` exits non-zero with a connection error, record as **CRIT**: "Cannot reach control plane node $CP1. Verify the node is up before running this skill."
If `talosctl health` exits non-zero with a health failure, record as **CRIT** with the specific error.
If etcd member count < 3 or learner count > 0, record as **WARN**.
If any member is unhealthy, record as **CRIT**.

### 2. Kubernetes layer (skip if --subsystem not k8s/all)

Run:
```bash
KUBECONFIG=$KUBECONFIG kubectl get nodes -o wide
KUBECONFIG=$KUBECONFIG kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
KUBECONFIG=$KUBECONFIG kubectl top nodes
```

If `kubectl get nodes` fails, record as **CRIT**: "Kubernetes API unreachable."
If `kubectl top nodes` fails (metrics-server unavailable), record as **WARN**: "Resource usage unavailable — metrics-server not running." Continue with other checks.
NotReady nodes: **CRIT**. CrashLoopBackOff or OOMKilled pods in non-completed state: **WARN**. Nodes above 90% CPU or memory: **WARN**.

### 3. Cilium layer (skip if --subsystem not cilium/all)

Run:
```bash
KUBECONFIG=$KUBECONFIG kubectl -n kube-system get pods -l k8s-app=cilium -o wide
KUBECONFIG=$KUBECONFIG kubectl get ciliumnode -o wide
```

If `kubectl get ciliumnode` returns no resources, record as **CRIT**: "No CiliumNode objects — Cilium may not be running."
Any Cilium agent not Running: **CRIT**. Stale or mismatched CiliumNode IPs: **WARN**.

### 4. LINSTOR/Storage layer (skip if --subsystem not storage/all)

Run:
```bash
KUBECONFIG=$KUBECONFIG kubectl linstor node list
KUBECONFIG=$KUBECONFIG kubectl linstor resource list
KUBECONFIG=$KUBECONFIG kubectl linstor storage-pool list
```

If `kubectl linstor` returns "unknown command", record as **WARN**: "kubectl-linstor plugin not installed — storage checks skipped." Continue with other layers.
Satellite OFFLINE or UNKNOWN: **CRIT**. Resources in Degraded/SyncTarget/Inconsistent state: **WARN**. Storage pools below 20% free: **WARN**.

### 5. PKI layer (skip if --subsystem not pki/all)

Run:
```bash
KUBECONFIG=$KUBECONFIG kubectl get clusterissuer
KUBECONFIG=$KUBECONFIG kubectl get certificate -A
```

If `kubectl get clusterissuer` returns no resources, record as **WARN**: "cert-manager not installed — PKI checks skipped." Continue with other layers.
ClusterIssuer not Ready: **CRIT**. Certificates expired or expiring within 7 days: **WARN**.

## Output

Present a health report table to the user:

```
| Layer   | Status | Issues |
|---------|--------|--------|
| Talos   | OK/WARN/CRIT | details |
| K8s     | OK/WARN/CRIT | details |
| Cilium  | OK/WARN/CRIT | details |
| Storage | OK/WARN/CRIT | details |
| PKI     | OK/WARN/CRIT | details |
```

List CRIT items first. For each issue, cite the relevant section from `docs/day2-operations.md` and the appropriate follow-up skill.

Optionally write a snapshot to `docs/cluster-health-<date>.md` if the user requests a record.

## Hard Rules

- Read-only: never modify cluster state. Observation only.
- Use `-n $CP1 -e $CP1` (first control plane IP from environment.yaml) for all talosctl commands. Never use VIP.
- Do not attempt automated remediation — report findings and point to the appropriate skill.
- If a command fails due to tool unavailability (linstor plugin, metrics-server), record as WARN and continue — do not stop the entire health check.
