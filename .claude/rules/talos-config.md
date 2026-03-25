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

Orchestration targets (use `make`):
- `make gen-configs` — decrypt secrets + generate all node configs with patch layering
- `make schematics` — create factory schematics via Image Factory API, write IDs to `.schematic-ids.mk`
- `make cilium-bootstrap` / `make cilium-bootstrap-check` — render and validate Cilium bootstrap manifest
- `make install-<node>` — initial config apply to fresh node (`--insecure`)
- `make bootstrap` — bootstrap etcd on node-01
- `make clean` / `make talosconfig` / `make gen-secrets`

Direct talosctl (do NOT use make wrappers):
- Apply config: `talosctl apply-config -n <ip> -e <ip> -f talos/generated/<role>/<node>.yaml`
- Dry-run: `talosctl apply-config -n <ip> -e <ip> -f talos/generated/<role>/<node>.yaml --dry-run`
- Upgrade: `talosctl apply-config ...` then `talosctl upgrade -n <ip> -e <ip> --image <install-image> --preserve --wait --timeout 10m`
- Upgrade K8s: `talosctl upgrade-k8s --to <version> -n <ip> -e <ip>` (run `make -C talos cilium-bootstrap-check` first)
- Validate: `talosctl validate --config <file> --mode metal --strict`

Install image resolution: `factory.talos.dev/metal-installer/<SCHEMATIC_ID>:<TALOS_VERSION>` (read from `.schematic-ids.mk` + `versions.mk`)

## Important Behaviors
- Boot parameter changes require `talosctl upgrade` — `talosctl apply-config` only activates sysctls
- `.schematic-ids.mk` tracks IDs; Factory API only called when schematic YAML modified
- `.versions.stamp` tracks `TALOS_VERSION` + `KUBERNETES_VERSION` — triggers config regeneration
- Changing `TALOS_VERSION` in Makefile is sufficient to update all install image URLs
- Makefile ordering: `config-path` helper MUST be defined before any `$(eval)` template that references it
