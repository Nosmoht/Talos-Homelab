---
paths:
  - "talos/**"
  - "docs/day0-setup.md"
  - "docs/day2-operations.md"
---

# Talos Operations Guardrails

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

## Hard Rules
- Never edit generated files under `talos/generated/` directly.
- Never switch to `metal-installer-secureboot` on this hardware.
- Never add `debugfs=off` to kernel args.
