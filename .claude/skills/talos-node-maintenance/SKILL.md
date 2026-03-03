---
name: talos-node-maintenance
description: Plan and execute safe Talos day-2 maintenance for one node, including dry-run, apply/upgrade choice, and post-change verification.
argument-hint: [node-name]
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, Write
---

# Talos Node Maintenance

Use this skill for routine Talos operations on one node (`apply`, `upgrade`, recovery checks).

## Inputs
- Required argument: node name (`node-01`, `node-gpu-01`).
- Node definitions: `talos/nodes/<node>.yaml`.

## Workflow

### 1. Resolve node metadata
- Read `talos/Makefile` to map node role and IP.
- Resolve whether node is control-plane, standard worker, or GPU worker.

### 2. Preflight checks
Run:
```bash
make -C talos gen-configs
make -C talos dry-run-<node>
```
If dry-run fails, stop and report error with likely root cause.

### 3. Decide operation
- Config-only/sysctl changes: `make -C talos apply-<node>`
- Boot args/extensions/version changes: `make -C talos upgrade-<node>`

### 4. Run verification
Use explicit endpoint (`-n` + `-e` node IP):
```bash
talosctl -n <ip> -e <ip> version
talosctl -n <ip> -e <ip> health
```
Then confirm node readiness in Kubernetes:
```bash
KUBECONFIG=/tmp/homelab-kubeconfig kubectl get node <node>
```

## Output
Write `docs/talos-maintenance-<node>-<yyyy-mm-dd>.md` with:
1. Change type (`apply` vs `upgrade`) and rationale
2. Commands executed
3. Verification results
4. Any rollback/recovery notes

## Hard Rules
- Never edit `talos/generated/**` directly.
- Never run operations through VIP when direct endpoint is required.
