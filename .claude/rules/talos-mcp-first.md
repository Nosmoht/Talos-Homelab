---
paths:
  - "talos/**"
  - "docs/day0-setup.md"
  - "docs/day2-operations.md"
---

# Talos Operations & MCP-First Policy

## Policy Statement

Use Talos MCP tools for all supported operations. Fall back to `talosctl` CLI only for operations with no MCP equivalent (see CLI-Only table below).

When a MCP tool fails: retry once, then fall back to CLI for the remainder of the session and log the fallback.

**Skill CLI-only exceptions:** Skills may use `talosctl get machineconfig -o yaml > <file>` for config backup to file, `talosctl upgrade-k8s` (no MCP equivalent), and bulk `/proc`/`/sys` reads in `analyze-node-hardware`. Planning skills (`plan-*`) may use `talosctl apply-config --dry-run` for validation only (B2: planning skills must not have mutating MCP tools). All other Talos operations must use MCP tools.

## Node Connectivity

- Use explicit node endpoint for operational commands: `talosctl -n <node-ip> -e <node-ip> ...`.
- Do not rely on VIP for operations known to fail via forwarding (dry-run/apply in degraded states).

## MCP Tool Mapping

### MCP-First (always prefer these)

| Operation | MCP Tool | Notes |
|---|---|---|
| Version info | `talos_version` | |
| Cluster health | `talos_health` | `control_plane_nodes`/`worker_nodes` params for override |
| Get resources | `talos_get` | Use `resource_type` param |
| List services | `talos_services` | |
| Etcd members/status | `talos_etcd` | |
| Service logs | `talos_logs` | |
| Kernel dmesg | `talos_dmesg` | |
| Containers | `talos_containers` | |
| Processes | `talos_processes` | |
| List filesystem | `talos_list_files` | |
| Read file | `talos_read_file` | |
| Events | `talos_events` | |
| Resource definitions | `talos_resource_definitions` | |
| Validate config (offline) | `talos_validate` | mode=metal (default), strict=false |
| Patch config | `talos_patch_config` | dry_run=true by default |
| Apply full config | `talos_apply_config` | dry_run=true by default; **always set dry_run explicitly** |
| Service action | `talos_service_action` | `talos_service_action(etcd, restart)` NOT supported (Talos API restriction) |
| OS Upgrade | `talos_upgrade` | **Always set `preserve=true` explicitly** — never rely on default |
| Rollback | `talos_rollback` | |
| Reboot | `talos_reboot` | **Always set `wait=true` and `timeout` explicitly** — never rely on defaults |
| Etcd snapshot | `talos_etcd_snapshot` | Requires exactly one CP node |
| Factory reset | `talos_reset` | IRREVERSIBLE — requires `confirm=true` + explicit `nodes`; never use in autonomous agents |

### CLI-Only (no safe MCP equivalent)

| Operation | CLI Command | Reason |
|---|---|---|
| Upgrade Kubernetes | `talosctl upgrade-k8s --to <ver> -n <ip> -e <ip>` | No MCP equivalent — FR #30 open |
| Config backup to file | `talosctl get mc -o yaml > /tmp/file` | MCP returns data in conversation context, not to file |
| Client version | `talosctl version --client` | MCP queries remote nodes only |

## Decision Flow

```
Need a Talos operation?
  → Is there a MCP tool for it? (see table above)
      YES → Use MCP tool
      NO  → Use talosctl CLI (CLI-Only list)
  → MCP tool fails?
      Retry once → still fails → CLI fallback for session, log it
```

## Critical Parameter Rules

These parameters must **always** be specified explicitly — never rely on defaults:

- `talos_upgrade`: set `preserve=true` (protects DRBD/LINSTOR EPHEMERAL partition from wipe)
- `talos_reboot`: set `wait=true` and `timeout` (ensures agent blocks until node is back)
- `talos_apply_config`: set `dry_run` explicitly (default is true, but always be explicit)
- `talos_reset`: requires `confirm=true` and explicit `nodes` array

## Change Classes

- Sysctl/config changes: `talosctl apply-config -n <ip> -e <ip> -f talos/generated/<role>/<node>.yaml`.
- Boot args/extensions/image changes: `talosctl apply-config` then `talosctl upgrade -n <ip> -e <ip> --image <install-image> --preserve --wait --timeout 10m`.
- Cluster-wide config refresh: regenerate first (`make -C talos gen-configs`).
- Install image resolution: read `talos/.schematic-ids.mk` + `talos/versions.mk` to construct `factory.talos.dev/metal-installer/<SCHEMATIC_ID>:<TALOS_VERSION>`.

## Safety Checklist

1. Confirm node role and impact (control plane vs worker vs GPU worker).
2. For reboot/upgrade, verify workload and DRBD placement before action.
3. Validate generated config exists under `talos/generated/` before apply.
4. Use dry-run where possible before apply.

## Apply-Config Gotchas

- **Patches that add new `interfaces:` entries: apply with `dry_run=false` directly.** Before applying, read the live `MachineConfig` via `talos_get type=MachineConfig`. If the target `interface:` name is absent from the live config, skip dry-run — `talos_apply_config dry_run=true` panics with `panic: runtime error: index out of range [N] with length N` when the patch introduces an interface entry that the diff engine has no existing object to diff against. The panic is a Talos diff-engine bug, not a config error; the real apply (`dry_run=false`) succeeds cleanly. If the target interface already exists in the live config, `dry_run=true` is safe and preferred.

## Upgrade Gotchas

- **Stale schematic IDs**: After editing `talos/talos-factory-schematic*.yaml`, re-run `make -C talos schematics` to update `.schematic-ids.mk`. `make -C talos validate-schematics` detects drift; `upgrade-*` Makefile targets run it automatically.
- `talosctl upgrade-k8s` requires `-n <node-ip> -e <node-ip>` — `--endpoint` is a different flag (proxy endpoint, not node target)
- **`hubble-generate-certs` Job blocks `upgrade-k8s`**: The Job has a hash-based name (`hubble-generate-certs-b36ef54b9b`); if it exists from a previous run, `upgrade-k8s` fails with immutable field error. Delete before running: `kubectl delete job -n kube-system -l k8s-app=hubble-generate-certs`
- **`upgrade-k8s` does NOT reliably update existing ConfigMaps**: When adding keys to existing ones (e.g., `enable-wireguard` in `cilium-config`), `upgrade-k8s` shows "no changes" and skips them. Workaround: `yq` extract + `kubectl apply --server-side --force-conflicts --field-manager=talos -f -`, then restart the DaemonSet

## Node Recovery

- **Stuck D-state nodes (DRBD)**: Only fixable with physical power cycle — no API recovery
- **Upgrade sequence lock on CSI unmount**: DRBD CSI volumes in D-state during `unmountPodMounts` deadlock the upgrade — `talosctl reboot`, `upgrade --force`, and `reset` all fail with "locked"; only physical power cycle recovers. Mitigate: `kubectl drain <node> --delete-emptydir-data --ignore-daemonsets --timeout=120s` before `talosctl upgrade` on DRBD nodes
- Etcd member removed: `talosctl reset --system-labels-to-wipe EPHEMERAL --reboot --graceful=false`
- Learner promotion is automatic (~1-2 min) after EPHEMERAL reset

## API Behavior

- `talosctl apply-config` with unchanged config is a no-op
- `kubectl delete pod` on static pods only recreates the mirror pod — real container keeps running
- kube-apiserver `$(POD_IP)` env var is frozen at container creation; survives kubelet restarts
- `talosctl service etcd restart` is NOT supported — etcd can't be restarted via API
- Maintenance mode `--insecure` only supports: `version`, `get disks`, `apply-config`
- `talosctl disks` deprecated — use `get disks`, `get systemdisk`, `get discoveredvolumes`

## Known Restrictions

- `talos_service_action(service=etcd, action=restart)` — NOT supported via Talos API. Use `talosctl service etcd restart` is also unsupported; etcd restarts require node reboot.
- `talos_reset` — excluded from autonomous agent `allowed-tools` due to irreversibility.
- **`talos_apply_config dry_run=true` panics on fresh interface additions** — see §Apply-Config Gotchas above for the decision rule. Short form: read live `MachineConfig` first; if the target interface is absent, use `dry_run=false` directly.

## Hard Rules

- Never edit generated files under `talos/generated/` directly.
- Never switch to `metal-installer-secureboot` on this hardware.
- Never add `debugfs=off` to kernel args.
