---
name: optimize-node-kernel
description: Research and apply optimized kernel parameters for a Talos node based on its hardware analysis. Reads hardware profile, researches best settings, patches config files.
argument-hint: [node-name]
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, WebSearch, WebFetch, Agent
---

# Optimize Node Kernel Parameters

Research and apply optimized kernel parameters for a Talos Kubernetes node. Uses the hardware analysis document as input, researches best settings for the specific hardware, and modifies the appropriate config files.

## Prerequisites

This skill requires a hardware analysis document at `docs/hardware-analysis-<node-name>.md`. If it doesn't exist, instruct the user:

> The hardware analysis for `<node-name>` doesn't exist yet. Please run `/analyze-node-hardware <node-name>` first to generate it.

## Step 1: Read Context

Read ALL of the following files before making any recommendations:

1. **Hardware analysis:** `docs/hardware-analysis-<node-name>.md` — the primary input
2. **Existing kernel tuning docs:**
   - `docs/kernel-tuning.md` — standard node tuning (understand what's already decided)
   - `docs/kernel-tuning-gpu.md` — GPU node tuning (if exists)
3. **Current config files (determine which ones apply to this node):**
   - `patches/common.yaml` — shared sysctls for ALL nodes
   - Role patch (determine from node labels or hardware analysis):
     - `patches/controlplane.yaml` for control plane nodes
     - `patches/worker-gpu.yaml` for GPU workers
     - Standard workers have no role patch (install image injected dynamically via Makefile)
   - `nodes/<node-name>.yaml` — node-specific config
   - Factory schematic:
     - `talos-factory-schematic.yaml` for standard nodes
     - `talos-factory-schematic-gpu.yaml` for GPU workers
4. **Talos KSPP defaults** (documented in kernel-tuning.md Section 3) — to avoid duplicating parameters Talos already enforces

## Step 2: Identify Tuning Opportunities

Based on the hardware analysis, identify optimization opportunities in these categories:

### CPU-Specific
- Governor: `performance` vs `schedutil` vs `powersave`
- C-States: `intel_idle.max_cstate` / `processor.max_cstate` settings
- Mitigations: `mitigations=auto` vs specific overrides based on vulnerability matrix
- Hyper-Threading: `nosmt` consideration (only if security requires it)
- Turbo Boost: BIOS recommendation if disabled

### GPU-Specific (if applicable)
- IOMMU mode: `iommu.strict=1` vs `iommu.strict=0` based on GPU workload
- PCIe ASPM: `pcie_aspm=off` for multi-GPU or mining boards
- NVIDIA module params: `NVreg_UsePageAttributeTable`, `NVreg_EnableResizableBar`, etc.
- BPF JIT hardening: whether to keep or remove the GPU override

### Storage-Specific
- I/O scheduler: `elevator=none` for SSD/NVMe, `mq-deadline` for HDD
- Dirty page tuning: `vm.dirty_ratio`, `vm.dirty_background_ratio` based on disk speed
- If node has mixed HDD+SSD, note that `elevator=none` as boot param affects ALL devices

### Memory-Specific
- THP: `transparent_hugepage=madvise` (standard for Kubernetes)
- Hugepages: whether to pre-allocate based on workload
- `vm.min_free_kbytes`: scale based on RAM size (64MB for 32GB, 128MB for 64GB+)
- Dirty page settings: adjust based on RAM amount

### Network-Specific
- TCP buffer sizes: based on NIC speed and capabilities
- Congestion control: `cubic` vs `bbr` based on network conditions
- USB NIC considerations: higher CPU overhead, adjust interrupt coalescing

### Security
- CPU vulnerability mitigations: verify all relevant ones are active
- IOMMU/VT-d: verify enabled and appropriate mode
- Memory protection: ASLR entropy, init_on_free

## Step 3: Research

Use WebSearch and WebFetch to research hardware-specific recommendations:

- Search for kernel tuning guides specific to the CPU model (e.g., "i7-7700K linux kernel tuning")
- Search for hardware-specific issues (e.g., "BTC B250C linux ASPM issues")
- Search for workload-specific tuning (e.g., "NVIDIA CUDA linux kernel parameters")
- Check NVIDIA documentation for recommended module parameters
- Check LINBIT/DRBD documentation for storage tuning relevant to the disk type
- Check Talos documentation for any version-specific kernel parameter notes

## Step 4: Categorize and Place Parameters

### Decision Rules for Patch Placement

| Parameter Type | Condition | Placement |
|---------------|-----------|-----------|
| **Sysctls** | Applies to ALL nodes (network, memory, security) | `patches/common.yaml` |
| **Sysctls** | Specific to GPU workloads | `patches/worker-gpu.yaml` |
| **Sysctls** | Specific to control plane (etcd tuning) | `patches/controlplane.yaml` |
| **Sysctls** | Unique to one node's hardware | `nodes/<node>.yaml` |
| **Boot parameters** | Applies to standard nodes | `talos-factory-schematic.yaml` |
| **Boot parameters** | Applies to GPU worker | `talos-factory-schematic-gpu.yaml` |
| **Kernel module params** | Role-specific module | Role patch (e.g., `worker-gpu.yaml`) |
| **BIOS settings** | Cannot be set via config | Document in recommendations only |

### Critical Rules

- **NEVER duplicate Talos KSPP defaults** (listed in kernel-tuning.md Section 3). These are already enforced by Talos and setting them again can cause conflicts.
- **NEVER duplicate parameters already in `common.yaml`** in role or node patches, unless intentionally overriding with a different value.
- **`--config-patch` APPENDS arrays** — if adding kernel modules, check that the module isn't already listed in a lower-precedence patch (common.yaml). Don't add the same module in both common and role patches.
- **Boot parameters require `talosctl upgrade`** — they are burned into the UKI image at install/upgrade time. Changing the schematic alone does nothing until upgrade is run.

## Step 5: Present Recommendations

Before making any changes, present a structured summary to the user:

```markdown
## Kernel Optimization Recommendations for <node-name>

### Changes to `patches/common.yaml` (affects ALL nodes)
| Sysctl | Current | Proposed | Rationale |
|--------|---------|----------|-----------|
| ... | ... | ... | ... |

### Changes to `patches/<role>.yaml`
| Parameter | Current | Proposed | Rationale |
|-----------|---------|----------|-----------|
| ... | ... | ... | ... |

### Changes to `nodes/<node>.yaml`
| Parameter | Current | Proposed | Rationale |
|-----------|---------|----------|-----------|
| ... | ... | ... | ... |

### Changes to `talos-factory-schematic*.yaml`
| Boot Parameter | Current | Proposed | Rationale |
|----------------|---------|----------|-----------|
| ... | ... | ... | ... |

### BIOS Recommendations (manual)
| Setting | Current | Recommended | Rationale |
|---------|---------|-------------|-----------|
| ... | ... | ... | ... |

### Not Recommended
| Parameter | Why Not |
|-----------|---------|
| ... | ... |
```

Wait for user approval before proceeding to Step 6.

## Step 6: Apply Approved Changes

For each approved change:

1. **Edit the appropriate YAML file** using the Edit tool
2. **Verify YAML validity** after each edit:
   ```bash
   # For Talos config patches, validate if possible:
   python3 -c "import yaml; yaml.safe_load(open('patches/common.yaml'))" 2>&1 || echo "YAML INVALID"
   ```
3. **Regenerate configs** (suggest but don't run without approval):
   ```bash
   make gen-configs
   ```

## Step 7: Update Documentation

After applying changes, update or create the kernel tuning documentation:

- If changes affect the GPU node, update `docs/kernel-tuning-gpu.md`
- If changes affect standard nodes, update `docs/kernel-tuning.md`
- Add new parameters with full rationale following the existing table format:
  `| Parameter | Value | Default | Rationale |`

## Step 8: Verification Commands

Provide verification commands for each change:

```bash
# After make apply-<node> or make upgrade-<node>:

# Verify sysctls
talosctl -n $NODE_IP -e $NODE_IP read /proc/sys/<sysctl-path>

# Verify boot parameters (only after upgrade)
talosctl -n $NODE_IP -e $NODE_IP read /proc/cmdline

# Verify module parameters
talosctl -n $NODE_IP -e $NODE_IP dmesg | grep -i <module-name>
```

## Important Notes

- Always use explicit endpoint (`-e $NODE_IP`) with talosctl.
- The kubeconfig is at `/tmp/homelab-kubeconfig`.
- Boot parameter changes require `make upgrade-<node>` (not just `make apply-<node>`).
- Some changes require a node reboot to take effect.
- DRBD volumes should be drained before rebooting to avoid stuck shutdown (D-state processes).
- Write all output and documentation in English.
- Follow the style conventions of existing docs (table-driven, rationale-heavy).
