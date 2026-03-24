---
name: talos-apply
description: Apply Talos config changes (sysctl, network, patches) to a single node with dry-run validation and health verification.
argument-hint: <node-name>
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, Write
---

# Talos Apply

You are a Talos Linux operator applying configuration changes to a single node. Think step-by-step: resolve node, validate, confirm, apply, verify.

## Reference Files

Read before proceeding:
- `references/apply-operations-guide.md` — Apply modes, etcd backup, quorum checks
- `.claude/rules/talos-operations.md` — Safety checklist, hard rules, change classes

## Scope Guard

This skill handles **config-only changes**: sysctl, network patches, machine config fields.

If the user's change involves image version, boot args, or extensions, stop and redirect:
> This change requires an OS image upgrade. Use `/talos-upgrade <node>` instead.

For planned multi-node rollouts, redirect to `/execute-talos-upgrade`.

## Inputs

- Required argument: node name (`node-01`, `node-gpu-01`, etc.)
- Node definitions: `talos/nodes/<node>.yaml`

## Workflow

### 1. Resolve node metadata

Read `talos/Makefile` to map node name → IP and role (control-plane, worker, GPU worker, Pi worker).

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

### 3. Generate and dry-run

```bash
make -C talos gen-configs
make -C talos dry-run-<node>
```

If dry-run fails, stop and report the error with likely root cause.

### 4. Show config diff

Show what will change by running the dry-run output against the node:
```bash
talosctl apply-config --nodes <ip> --endpoints <ip> --file talos/generated/<role>/<node>.yaml --dry-run
```
Where `<role>` is `controlplane` for CP nodes or `worker` for all others.

Present the diff to the user.

### 5. User confirmation gate

Present the planned operation and wait for explicit approval:

```
## Apply Plan: <node>
- **Node:** <node> (<role>, <ip>)
- **Operation:** apply (config change)
- **Mode:** auto (default) | staged | no-reboot
- **What changed:** <summary from diff>
- **Risk:** <reboot possible if mode=auto and config requires it>
- **Rollback:** re-apply previous config

Proceed? (yes/no)
```

### 6. Apply

After user confirms:
```bash
make -C talos apply-<node>
```

This uses `--mode=auto` by default. If the user requested a different mode, use `talosctl apply-config` directly:
- CP under load: `talosctl apply-config --mode=staged -n <ip> -e <ip> -f talos/generated/<role>/<node>.yaml`
- Safe probe: `talosctl apply-config --mode=no-reboot -n <ip> -e <ip> -f talos/generated/<role>/<node>.yaml`

### 7. Verify health

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
KUBECONFIG=/tmp/homelab-kubeconfig kubectl get node <node>
```

### 8. Write maintenance report

Present the completed report to the user for review. After user confirmation, write `docs/talos-maintenance-<node>-<yyyy-mm-dd>.md`:

```markdown
# Talos Maintenance: <node> (<yyyy-mm-dd>)

## Change Summary
- **Node:** <node> (<role>, <ip>)
- **Operation:** apply
- **Mode:** auto | staged | no-reboot
- **Rationale:** <what changed and why>

## Commands Executed
1. `<command>` — <result>

## Verification Results
- talosctl version: <version confirmed>
- talosctl health: <healthy|issues>
- etcd status: <quorum intact|N/A for workers>
- kubectl get node: <Ready|NotReady>

## Recovery Notes
<any issues encountered, or "None — operation completed successfully">
```

## Hard Rules

- Never edit `talos/generated/**` directly.
- Never use VIP for direct operations — always use explicit `-n <ip> -e <ip>`.
- Never operate on a CP node with degraded etcd quorum.
- This skill does NOT do upgrades — redirect to `/talos-upgrade`.
