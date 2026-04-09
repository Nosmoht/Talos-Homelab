---
paths:
  - "talos/**"
  - "docs/day0-setup.md"
  - "docs/day2-operations.md"
---

# Talos Operations Guardrails

## MCP-First Policy
Use Talos MCP tools instead of `talosctl` CLI wherever an MCP equivalent exists.
See `.claude/rules/talos-mcp-first.md` for the full mapping and CLI-only exceptions.

## Node Connectivity
- Use explicit node endpoint for operational commands: `talosctl -n <node-ip> -e <node-ip> ...`.
- Do not rely on VIP for operations known to fail via forwarding (dry-run/apply in degraded states).

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

## Hard Rules
- Never edit generated files under `talos/generated/` directly.
- Never switch to `metal-installer-secureboot` on this hardware.
- Never add `debugfs=off` to kernel args.
