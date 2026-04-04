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

Use throughout this skill:
- `KUBECONFIG=<kubeconfig>` for all kubectl commands
- `-n <node-ip> -e <node-ip>` for all talosctl commands (never use VIP)

## Reference Files

Read before acting:
- `docs/day2-operations.md` — "Cluster Health Checks" section (commands per subsystem, thresholds)
- `.claude/rules/talos-operations.md` — etcd quorum thresholds, D-state recovery guidance

## Inputs

- `$ARGUMENTS`: Optional `--subsystem` filter. Supported values: `talos`, `k8s`, `cilium`, `storage`, `pki`, `all`. Default: `all`.

## Scope Guard

This is a read-only health check. If remediation is needed, suggest the appropriate skill:
- ArgoCD sync failures → `/gitops-health-triage`
- Storage degraded/DRBD issues → `/linstor-storage-triage`
- Cilium policy drops → `/cilium-policy-debug`
- Node config or upgrade needed → `/talos-apply` or `/talos-upgrade`

Do not attempt remediation from this skill.

## Workflow

### 1. Talos layer (skip if --subsystem not talos/all)

Run:
```bash
talosctl -n <cp1-ip> -e <cp1-ip> health --control-plane-nodes <cp1-ip>,<cp2-ip>,<cp3-ip>
talosctl -n <cp1-ip> -e <cp1-ip> etcd members
talosctl -n <cp1-ip> -e <cp1-ip> etcd status
```

Evaluate:
- If `talosctl health` exits non-zero: **CRIT**
- If etcd member count < 3 or learner count > 0: **WARN**
- If any member is unhealthy: **CRIT**

### 2. Kubernetes layer (skip if --subsystem not k8s/all)

Run:
```bash
KUBECONFIG=<kubeconfig> kubectl get nodes -o wide
KUBECONFIG=<kubeconfig> kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
KUBECONFIG=<kubeconfig> kubectl top nodes
```

Evaluate:
- NotReady nodes: **CRIT**
- CrashLoopBackOff or OOMKilled pods in non-completed state: **WARN**
- Nodes above 90% CPU or memory: **WARN**

### 3. Cilium layer (skip if --subsystem not cilium/all)

Run:
```bash
KUBECONFIG=<kubeconfig> kubectl -n kube-system get pods -l k8s-app=cilium -o wide
KUBECONFIG=<kubeconfig> kubectl get ciliumnode -o wide
```

Evaluate:
- Any Cilium agent not Running: **CRIT**
- Stale or mismatched CiliumNode IPs: **WARN**

### 4. LINSTOR/Storage layer (skip if --subsystem not storage/all)

Run:
```bash
KUBECONFIG=<kubeconfig> kubectl linstor node list
KUBECONFIG=<kubeconfig> kubectl linstor resource list
KUBECONFIG=<kubeconfig> kubectl linstor storage-pool list
```

Evaluate:
- Satellite OFFLINE or UNKNOWN: **CRIT**
- Resources in Degraded/SyncTarget/Inconsistent state: **WARN**
- Storage pools below 20% free: **WARN**

### 5. PKI layer (skip if --subsystem not pki/all)

Run:
```bash
KUBECONFIG=<kubeconfig> kubectl get clusterissuer
KUBECONFIG=<kubeconfig> kubectl get certificate -A
```

Evaluate:
- ClusterIssuer not Ready: **CRIT**
- Certificates expired or expiring within 7 days: **WARN**

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
- Use explicit `-n <ip> -e <ip>` for all talosctl commands. Never use VIP or omit endpoints.
- Do not attempt automated remediation — report findings and point to the appropriate skill.
