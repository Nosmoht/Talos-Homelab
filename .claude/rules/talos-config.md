---
paths:
  - "talos/patches/**"
  - "talos/Makefile"
  - "talos/.schematic-ids.mk"
---

# Talos Config Generation & Makefile

## Patch Files
- `talos/patches/common.yaml` — shared: CNI none, proxy disabled, kubePrism, DRBD modules, kubelet args, NTP, search domain
- `talos/patches/controlplane.yaml` — CP settings, extraManifests (cert-approver, metrics-server, Cilium URL)
- `talos/patches/worker-gpu.yaml` — NVIDIA kernel modules (`NVreg_UsePageAttributeTable=1`), no sysctls (Talos KSPP defaults)
- `rp_filter` and `log_martians` must be `0` in `common.yaml` — Cilium BPF bypasses kernel FIB, causing false-positive martian drops

## Config Generation Flow
- `talos/secrets.yaml` is SOPS-encrypted; `gen-configs` auto-decrypts to `talos/.secrets.dec.yaml` (gitignored)
- Patches applied in order: `common.yaml` → role patch → node patch (later patches override scalars)
- Install images NOT in patch files — injected as inline `--config-patch` from `INSTALL_IMAGE`/`GPU_INSTALL_IMAGE`
- `--config-patch` APPENDS arrays, not replaces — don't duplicate array entries across common and role patches
- HostnameConfig quirk: use `auto: null` in node patches + yq post-processing to remove `auto: stable`
- Strategic merge on interfaces APPENDS arrays — doesn't merge by deviceSelector; keep VIP in per-node patches

## Makefile Targets (`talos/Makefile`)
- `make install-<node>` — initial config apply to fresh node (`--insecure`)
- `make bootstrap` — bootstrap etcd on node-01
- `make apply-<node>` — apply config to node
- `make dry-run-<node>` — dry-run config apply
- `make upgrade-<node>` — apply config + upgrade install image (auto-selects standard vs GPU)
- `make schematics` — create factory schematics via Image Factory API, write IDs to `.schematic-ids.mk`
- `make gen-configs` / `make clean` / `make talosconfig` / `make gen-secrets`
- All targets auto-trigger: secrets decryption → config generation

## Important Behaviors
- Boot parameter changes require `make upgrade-<node>` — `make apply-<node>` only activates sysctls
- `.schematic-ids.mk` tracks IDs; Factory API only called when schematic YAML modified
- `.versions.stamp` tracks `TALOS_VERSION` + `KUBERNETES_VERSION` — triggers config regeneration
- Changing `TALOS_VERSION` in Makefile is sufficient to update all install image URLs
- Makefile ordering: `config-path` helper MUST be defined before any `$(eval)` template that references it
