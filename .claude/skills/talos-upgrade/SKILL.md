---
name: talos-upgrade
description: Upgrade a single Talos node's OS image (version bump, extension changes, boot args) with drain, DRBD safety, and rollback support.
argument-hint: <node-name>
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, Write
---

# Talos Upgrade

## Environment Setup

Read `.claude/environment.yaml` to load cluster-specific values (node IPs, kubeconfig path).
If the file is missing, tell the user: "Copy `.claude/environment.example.yaml` to `.claude/environment.yaml` and fill in your cluster details."

Use throughout this skill:
- `KUBECONFIG=<kubeconfig>` for all `kubectl` commands
- `-n <node-ip> -e <node-ip>` for all `talosctl` commands targeting a node

You are a Talos Linux operator upgrading a single node's OS image. Think step-by-step: resolve node, validate, check storage safety, confirm, drain, upgrade, verify, uncordon.

## Reference Files

Read before proceeding:
- `references/upgrade-operations-guide.md` — `--preserve`, drain/uncordon, rollback, etcd backup/quorum
- `.claude/rules/talos-operations.md` — Safety checklist, hard rules, change classes

## Scope Guard

This skill handles **image/version/extension/boot-arg changes** for a single node.

If the user's change is config-only (sysctl, network patches), stop and redirect:
> This is a config-only change. Use `/talos-apply <node>` instead.

For planned multi-node version rollouts with an approved plan, redirect to `/execute-talos-upgrade`.

## Inputs

- Required argument: node name (`node-01`, `node-gpu-01`, etc.)
- Node definitions: `talos/nodes/<node>.yaml`

## Workflow

### 1. Resolve node metadata

Read `talos/Makefile` to map node name → IP, role (control-plane, worker, GPU worker, Pi worker), and install image.

### 2. Preflight (control-plane only)

If node is control-plane, take backups first:
```bash
talosctl etcd snapshot /tmp/etcd-backup-$(date +%Y%m%d).snapshot -n <ip> -e <ip>
talosctl get machineconfig -n <ip> -e <ip> -o yaml > /tmp/machineconfig-<node>-$(date +%Y%m%d).yaml
```

Verify etcd quorum:
```bash
talosctl etcd status -n <ip> -e <ip>
```
If quorum is degraded (fewer than (n/2)+1 members healthy), stop and report. Do not operate on a CP node with pre-existing quorum issues.

### 3. Generate and validate

```bash
make -C talos gen-configs
make -C talos dry-run-<node>
```

If dry-run fails, stop and report the error with likely root cause.

Note: `talosctl upgrade` does not support `--dry-run` ([siderolabs/talos#10804](https://github.com/siderolabs/talos/issues/10804)). The dry-run above validates config generation only.

### 4. DRBD/LINSTOR safety check

Check storage replica placement before draining:
```bash
KUBECONFIG=<kubeconfig> kubectl linstor volume list --nodes <node>
```

Verify all volumes on this node have at least one healthy replica on another node. If any volume has only one replica and it lives on this node, stop and report:
> Volume <name> has no replica on other nodes. Upgrading this node risks data unavailability. Resolve replica placement before proceeding.

### 5. User confirmation gate

Present the planned operation and wait for explicit approval:

```
## Upgrade Plan: <node>
- **Node:** <node> (<role>, <ip>)
- **Operation:** upgrade (OS image change)
- **Current image:** <from talosctl version output or Makefile>
- **Target image:** <from Makefile IMAGE variable>
- **Risk:** node will reboot
- **Rollback:** talosctl rollback -n <ip> -e <ip>

Proceed? (yes/no)
```

### 6. Drain

```bash
KUBECONFIG=<kubeconfig> kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --timeout=120s
```

The 120s timeout is critical — DRBD CSI volumes in D-state during `unmountPodMounts` can deadlock the upgrade with no API recovery if drain is skipped.

### 7. Upgrade

```bash
make -C talos upgrade-<node>
```

This applies config and upgrades the install image with `--preserve` (prevents EPHEMERAL partition wipe).

### 8. Verify health

Wait for the node to come back, then verify:
```bash
talosctl -n <ip> -e <ip> version
talosctl -n <ip> -e <ip> health
```

For control-plane nodes, also verify etcd:
```bash
talosctl etcd members -n <ip> -e <ip>
talosctl etcd status -n <ip> -e <ip>
```
Confirm all members show `started` before declaring success.

Then confirm node readiness:
```bash
KUBECONFIG=<kubeconfig> kubectl get node <node>
```

If the node remains NotReady, check for pending CSR approval:
```bash
KUBECONFIG=<kubeconfig> kubectl get csr
```

### 9. Uncordon

Only after health verification passes:
```bash
KUBECONFIG=<kubeconfig> kubectl uncordon <node>
```

### 10. Post-upgrade DRBD verification

Confirm storage reconnection:
```bash
KUBECONFIG=<kubeconfig> kubectl linstor volume list --nodes <node>
```

All volumes should show `UpToDate` status.

### 11. Write maintenance report

Present the completed report to the user for review. After user confirmation, write `docs/talos-maintenance-<node>-<yyyy-mm-dd>.md`:

```markdown
# Talos Maintenance: <node> (<yyyy-mm-dd>)

## Change Summary
- **Node:** <node> (<role>, <ip>)
- **Operation:** upgrade
- **Previous image:** <previous>
- **New image:** <new>
- **Rationale:** <what changed and why>

## Commands Executed
1. `<command>` — <result>

## Verification Results
- talosctl version: <version confirmed>
- talosctl health: <healthy|issues>
- etcd status: <quorum intact|N/A for workers>
- kubectl get node: <Ready|NotReady>
- DRBD volumes: <UpToDate|issues>

## Recovery Notes
<any rollback actions taken, or "None — operation completed successfully">
```

## Hard Rules

- Never edit `talos/generated/**` directly.
- Never use VIP for direct operations — always use explicit `-n <ip> -e <ip>`.
- Never operate on a CP node with degraded etcd quorum.
- Never skip drain on DRBD nodes — D-state deadlock requires physical power cycle.
- Ensure the Makefile `upgrade-<node>` target passes `--preserve`.
- Never conflate OS upgrade with `talosctl upgrade-k8s` (Kubernetes version upgrade).
- This skill does NOT do config-only applies — redirect to `/talos-apply`.
