---
name: talos-node-maintenance
description: Plan and execute safe Talos day-2 maintenance for one node, including dry-run, apply/upgrade choice, and post-change verification.
argument-hint: [node-name]
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, Write
---

> **Deprecated:** Superseded by `/talos-apply` (config changes) and `/talos-upgrade` (image/version changes).

# Talos Node Maintenance

## Environment Setup

Read `.claude/environment.yaml` to load cluster-specific values (node IPs, kubeconfig path).
If the file is missing, tell the user: "Copy `.claude/environment.example.yaml` to `.claude/environment.yaml` and fill in your cluster details."

Use throughout this skill:
- `KUBECONFIG=<kubeconfig>` for all `kubectl` commands
- `-n <node-ip> -e <node-ip>` for all `talosctl` commands targeting a node
- Node inventory from `nodes.control_plane`, `nodes.workers`, `nodes.gpu_workers`

You are a Talos Linux maintenance engineer performing safe, single-node day-2 operations. Think step-by-step: resolve node metadata, verify safety, choose the minimal operation needed, verify success, document.

## Reference Files

Read before proceeding:
- `references/talos-operations-guide.md` — Apply modes, `--preserve`, etcd backup, drain, rollback
- `.claude/rules/talos-operations.md` — Safety checklist, hard rules, change classes

## Inputs

- Required argument: node name (`node-01`, `node-gpu-01`).
- Node definitions: `talos/nodes/<node>.yaml`.

## Workflow

### 1. Resolve node metadata

- Read `talos/Makefile` to map node role and IP.
- Resolve whether node is control-plane, standard worker, or GPU worker.

### 2. Preflight checks

If node is control-plane, take backups first:
```bash
talosctl etcd snapshot /tmp/etcd-backup-$(date +%Y%m%d).snapshot -n <ip> -e <ip>
talosctl get machineconfig -n <ip> -e <ip> -o yaml > /tmp/machineconfig-<node>-$(date +%Y%m%d).yaml
```

If node is control-plane, verify etcd quorum before proceeding:
```bash
talosctl etcd status -n <ip> -e <ip>
```
If quorum is degraded (fewer than (n/2)+1 members healthy), stop and report. Do not operate on a CP node with pre-existing quorum issues.

Then run config generation and dry-run:
```bash
make -C talos gen-configs
talosctl apply-config -n <ip> -e <ip> -f talos/generated/<role>/<node>.yaml --dry-run
```
Where `<role>` is `controlplane` for CP nodes or `worker` for all others.

If dry-run fails, stop and report error with likely root cause.

Note: `talosctl upgrade` does not support `--dry-run`; the dry-run above validates config generation only.

### 3. Decide operation

Present the planned operation to the user and wait for explicit approval before executing:

```
## Maintenance Plan: <node>
- **Node:** <node> (<role>, <ip>)
- **Operation:** apply | upgrade
- **Reason:** <what changed>
- **Risk:** <reboot expected? etcd impact?>
- **Rollback:** talosctl rollback -n <ip> -e <ip>

Proceed? (yes/no)
```

After user confirms:

- Config-only/sysctl changes: `talosctl apply-config -n <ip> -e <ip> -f talos/generated/<role>/<node>.yaml`
  - For CP nodes when the cluster is under active load, prefer staged mode: `talosctl apply-config --mode=staged -n <ip> -e <ip> -f talos/generated/<role>/<node>.yaml`
  - If uncertain whether a reboot is required, first attempt `--mode=no-reboot`; if it fails, escalate to `--mode=auto`.
- Boot args/extensions/version changes:
  1. Check DRBD/LINSTOR replica placement before draining:
     ```bash
     KUBECONFIG=<kubeconfig> kubectl linstor volume list --nodes <node>
     ```
     Verify all volumes on this node have at least one healthy replica on another node. If any volume has only one replica and it is on this node, stop and report.
  2. Drain the node:
     ```bash
     KUBECONFIG=<kubeconfig> kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
     ```
  2. Run the upgrade (resolve install image from `talos/.schematic-ids.mk` + `talos/versions.mk`):
     ```bash
     talosctl apply-config -n <ip> -e <ip> -f talos/generated/<role>/<node>.yaml
     talosctl upgrade -n <ip> -e <ip> --image <install-image> --preserve --wait --timeout 10m
     ```
  3. Uncordon after verification passes (Step 4):
     ```bash
     KUBECONFIG=<kubeconfig> kubectl uncordon <node>
     ```

Note: Kubernetes version upgrades are separate (`talosctl upgrade-k8s`). Do not conflate OS upgrades with Kubernetes version changes.

### 4. Run verification

Use explicit endpoint (`-n` + `-e` node IP):
```bash
talosctl -n <ip> -e <ip> version
talosctl -n <ip> -e <ip> health
```

If node is control-plane, additionally verify etcd quorum:
```bash
talosctl etcd members -n <ip> -e <ip>
talosctl etcd status -n <ip> -e <ip>
```
Confirm all members are `started` before declaring success.

Then confirm node readiness in Kubernetes:
```bash
KUBECONFIG=<kubeconfig> kubectl get node <node>
```

If the upgrade boots into a broken state, recover with: `talosctl rollback -n <ip> -e <ip>`

## Output

Present the completed report to the user for review. After user confirmation, write `docs/talos-maintenance-<node>-<yyyy-mm-dd>.md` using this template:

```markdown
# Talos Maintenance: <node> (<yyyy-mm-dd>)

## Change Summary
- **Node:** <node> (<role>, <ip>)
- **Operation:** apply | upgrade
- **Rationale:** <what changed and why>

## Commands Executed
1. `<command>` — <result>

## Verification Results
- talosctl version: <version confirmed>
- talosctl health: <healthy|issues>
- etcd status: <quorum intact|N/A for workers>
- kubectl get node: <Ready|NotReady>

## Recovery Notes
<any rollback actions taken, or "None — operation completed successfully">
```

## Hard Rules

- Never edit `talos/generated/**` directly.
- Never run operations through VIP when direct endpoint is required.
- Never operate on more than one control-plane node at a time. Confirm all CP nodes are Ready and etcd quorum is intact before beginning any CP maintenance.
- Ensure the Makefile `upgrade-<node>` target passes `--preserve` (prevents EPHEMERAL partition wipe).
