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
- Sysctl/config changes: `make -C talos apply-<node>`.
- Boot args/extensions/image changes: `make -C talos upgrade-<node>`.
- Cluster-wide config refresh: regenerate first (`make -C talos gen-configs`).

## Safety Checklist
1. Confirm node role and impact (control plane vs worker vs GPU worker).
2. For reboot/upgrade, verify workload and DRBD placement before action.
3. Validate generated config exists under `talos/generated/` before apply.
4. Use dry-run where possible before apply.

## Hard Rules
- Never edit generated files under `talos/generated/` directly.
- Never switch to `metal-installer-secureboot` on this hardware.
- Never add `debugfs=off` to kernel args.
