# Kernel-Tuning: GPU Worker (node-gpu-01)

> **Scope:** node-gpu-01 (BTC B250C mining board, 3x NVIDIA GA104)
> **Created:** 2026-02-28
> **Talos:** v1.12.4 | **Kubernetes:** v1.35.0 | **Cilium:** v1.19.0 (eBPF kube-proxy replacement)
> **Companion document:** [kernel-tuning.md](kernel-tuning.md) covers node-01 through node-06

---

## Table of Contents

1. [Hardware Profile](#1-hardware-profile)
2. [PCI Device Inventory](#2-pci-device-inventory)
3. [USB Device Inventory](#3-usb-device-inventory)
4. [NFD Feature Summary](#4-nfd-feature-summary)
5. [CPU Vulnerability Matrix (Kaby Lake)](#5-cpu-vulnerability-matrix-kaby-lake)
6. [Current Configuration State](#6-current-configuration-state)
7. [Boot Parameter Gap Analysis](#7-boot-parameter-gap-analysis)
8. [GPU-Specific Considerations](#8-gpu-specific-considerations)
9. [Recommendations](#9-recommendations)
10. [Verification](#10-verification)
11. [Sources](#11-sources)

---

## 1. Hardware Profile

node-gpu-01 is a repurposed cryptocurrency mining rig. The BTC B250C is a mining-specific
motherboard with multiple PCIe x1 slots (typically used with risers). It runs 3x NVIDIA
GA104 GPUs for compute workloads.

### System Overview

| Property | Value |
|----------|-------|
| Board | BTC B250C (mining motherboard) |
| Vendor | OEM |
| CPU | Intel Core i7-7700K @ 4.20GHz (Kaby Lake, Family 6, Model 158, Stepping 9) |
| Cores/Threads | 4C / 8T (Hyper-Threading enabled) |
| Microcode | 0xf8 (updated at boot via intel-ucode extension, from 0x9a) |
| RAM | 32 GB DDR4 (non-ECC, single-channel likely) |
| Swap | None |
| NUMA | Not present (single socket) |
| Boot Disk | `/dev/sda` — HDD (rotational=1), mq-deadline scheduler |
| Data Disk | `/dev/sdb` — SSD (rotational=0), 450 GiB XFS (WWN: naa.5001b444a5673347) |
| Second SSD | `/dev/sdc` — SSD (rotational=0) |
| NVMe | None |
| Active NIC | enp0s20f0u2 — USB 3.0 Realtek RTL8153 GbE (r8152 driver), MAC 00:e0:3c:68:46:45 |
| Unused NIC | enp4s0 — PCIe Realtek RTL8136 Fast Ethernet (r8169 driver), operstate=down |
| GPUs | 3x NVIDIA GA104 (PCIe slots 01:00.0, 02:00.0, 03:00.0) |
| iGPU | Intel HD Graphics 630 (00:02.0, i915 driver) |
| Kernel | Linux 6.18.9-talos (gcc 15.2.0) |

### Key Differences vs Standard Nodes (M710q/M920q)

| Attribute | Standard Nodes (node-01..06) | GPU Worker (node-gpu-01) | Impact |
|-----------|------------------------------|--------------------------|--------|
| Motherboard | Lenovo ThinkCentre (OEM quality) | BTC B250C (mining board) | PCIe ASPM unreliable on mining boards |
| CPU | Skylake/Coffee Lake (various) | Kaby Lake i7-7700K | Same vulnerability surface as Skylake |
| Boot Disk | SATA SSD | SATA HDD | Slower boot, different I/O scheduler needs |
| Data Disk | NVMe (PCIe 3.0 x2/x4) | SATA SSD | Lower throughput, no NVMe optimizations |
| NIC | Intel I219-V/LM (e1000e), PCIe | Realtek RTL8153 (r8152), USB 3.0 | USB NIC = higher CPU overhead, no hardware offloads |
| GPUs | None (or iGPU only) | 3x NVIDIA GA104 + iGPU | IOMMU groups, PCIe bandwidth, DMA considerations |
| Factory Schematic | `talos-factory-schematic.yaml` | `talos-factory-schematic-gpu.yaml` | Separate schematic with NVIDIA extensions |
| Role Patch | `controlplane.yaml` (CP) / none (workers) | `worker-gpu.yaml` | NVIDIA modules, bpf_jit_harden override |

### Storage Profile

| Device | Type | Scheduler | Role | Notes |
|--------|------|-----------|------|-------|
| `/dev/sda` | HDD (rotational) | mq-deadline | Boot disk (Talos install) | `elevator=none` not ideal for HDD — mq-deadline is better default |
| `/dev/sdb` | SSD | — | Data (LINSTOR/DRBD, 450GiB XFS) | WWN: naa.5001b444a5673347 |
| `/dev/sdc` | SSD | — | Additional storage | — |

**Note on I/O scheduler:** The standard nodes use `elevator=none` because they only have
SSDs and NVMe. node-gpu-01 has a rotational HDD as boot disk — `mq-deadline` is the correct
scheduler for HDDs (provides seek optimization). The `elevator=none` boot parameter in the
GPU schematic would force `none` globally, which is suboptimal for the HDD. However, Talos
installs to the boot disk and rarely does heavy I/O on it after boot, so the impact is minimal.

### Network Profile

| Interface | Driver | Type | Speed | Status | Notes |
|-----------|--------|------|-------|--------|-------|
| enp0s20f0u2 | r8152 | USB 3.0 Gigabit Ethernet | 1000 Mbps | UP | Primary NIC, Realtek RTL8153 chipset |
| enp4s0 | r8169 | PCIe Fast Ethernet | — | DOWN | Realtek RTL8136, unused |

**USB NIC considerations:**
- Higher CPU overhead than PCIe NICs (USB protocol stack in kernel)
- No hardware TCP/UDP checksum offload (CPU must compute checksums)
- Latency slightly higher than PCIe NICs (~50-100µs additional)
- Adequate for 1 GbE throughput but not optimal for latency-sensitive workloads
- MAC address `00:e0:3c:68:46:45` pinned in `nodes/node-gpu-01.yaml` via `hardwareAddr`

---

## 2. PCI Device Inventory

| BDF | Vendor:Device | Class | Description |
|-----|---------------|-------|-------------|
| 0000:00:00.0 | 8086:591f | 0600 | Intel Host Bridge (Kaby Lake-H) |
| 0000:00:01.0 | 8086:1901 | 0604 | PCIe Root Port (x16 slot) |
| 0000:00:02.0 | 8086:5912 | 0300 | Intel HD Graphics 630 (iGPU) |
| 0000:00:04.0 | 8086:xxxx | — | Intel DPTF Thermal Management |
| 0000:00:14.0 | 8086:xxxx | — | Intel USB 3.0 xHCI Host Controller |
| 0000:00:16.0 | 8086:xxxx | — | Intel Management Engine Interface |
| 0000:00:17.0 | 8086:xxxx | — | Intel AHCI SATA Controller |
| 0000:00:1b.0 | 8086:xxxx | 0604 | PCIe Root Port (GPU slot 2) |
| 0000:00:1b.7 | 8086:xxxx | 0604 | PCIe Root Port (GPU slot 3) |
| 0000:00:1c.0 | 8086:xxxx | 0604 | PCIe Root Port (Ethernet) |
| 0000:00:1f.0 | 8086:xxxx | — | Intel LPC/ISA Bridge |
| 0000:00:1f.2 | 8086:xxxx | — | Intel PMC (Power Management Controller) |
| 0000:00:1f.4 | 8086:xxxx | — | Intel SMBus Controller |
| **0000:01:00.0** | **10de:2484** | **0300** | **NVIDIA GA104** (RTX 3070-class), subsystem 10de:146b |
| 0000:01:00.1 | 10de:228b | 0403 | NVIDIA GA104 HD Audio |
| **0000:02:00.0** | **10de:2486** | **0300** | **NVIDIA GA104** (RTX 3060Ti/3070-class), subsystem 10de:147a |
| 0000:02:00.1 | 10de:228b | 0403 | NVIDIA GA104 HD Audio |
| **0000:03:00.0** | **10de:2486** | **0300** | **NVIDIA GA104** (RTX 3060Ti/3070-class), subsystem 10de:147a |
| 0000:03:00.1 | 10de:228b | 0403 | NVIDIA GA104 HD Audio |
| 0000:04:00.0 | 10ec:8136 | 0200 | Realtek RTL8136 PCIe Fast Ethernet (unused) |

### IOMMU Groups

| Group | Devices | Notes |
|-------|---------|-------|
| 0 | 0000:00:02.0 (Intel iGPU) | Isolated |
| 1 | 0000:00:00.0 (Host Bridge) | — |
| 2 | 0000:00:01.0 + 0000:01:00.0 + 0000:01:00.1 | PCIe bridge + GPU 0 + Audio |
| 13–15 | GPUs 1, 2, additional slots | One GPU per group |

---

## 3. USB Device Inventory

| Vendor:Device | Class | Serial | Description |
|---------------|-------|--------|-------------|
| 0bda:8153 | ff | D01300E03C684645 | Realtek RTL8153 USB GbE (active NIC) |
| 0930:6545 | 08 (storage) | 001D92AD6BA9B950D32B0531 | Kingston USB storage |
| 1a86:e2e3 | 03 (HID) | — | QinHeng HID device |
| 046a:0011 | 03 (HID) | — | Cherry keyboard/HID |
| 1d6b:0002 | 09 (hub) | — | Linux Foundation USB 2.0 Hub |
| 1d6b:0003 | 09 (hub) | — | Linux Foundation USB 3.0 Hub |

---

## 4. NFD Feature Summary

Key NFD labels and features discovered on node-gpu-01:

### CPU Features

| Feature | Value | Notes |
|---------|-------|-------|
| cpu-model.vendor_id | Intel | — |
| cpu-model.family | 6 | — |
| cpu-model.id | 158 | Kaby Lake |
| cpu-hardware_multithreading | true | HT active (4C/8T) |
| cpu-pstate.scaling_governor | powersave | **Not performance** — schematic boot params not applied |
| cpu-pstate.status | active | Intel P-State driver active |
| cpu-pstate.turbo | false | **Turbo Boost disabled in BIOS** |
| cpu-cstate.enabled | true | C-States active (max_cstate=0 not applied) |
| cpu-security.sgx.enabled | true | SGX active, EPC=98041856 bytes (~93MB) |
| cpu-security.sev.* | true | Incorrect — AMD SEV not available on Intel, NFD false positive |

### Relevant CPUID Flags

`ADX`, `AESNI`, `AVX`, `AVX2`, `FLUSH_L1D`, `FMA3`, `IA32_ARCH_CAP`, `IBPB`,
`MD_CLEAR`, `MPX`, `RTM_ALWAYS_ABORT`, `SPEC_CTRL_SSBD`, `SRBDS_CTRL`, `STIBP`, `VMX`

### Storage & Memory

| Feature | Value | Notes |
|---------|-------|-------|
| storage-nonrotationaldisk | present | At least one SSD detected |
| memory.numa.is_numa | false | Single socket |
| memory.swap.enabled | false | No swap |
| memory.hugepages.enabled | false | No hugepages allocated |

### PCI & USB Signatures

| Feature | Meaning |
|---------|---------|
| pci-0300_10de.present | NVIDIA GPU (class 0300, vendor 10de) |
| pci-0300_8086.present | Intel iGPU (class 0300, vendor 8086) |
| usb-ff_0bda_8153.present | Realtek USB Ethernet adapter |

---

## 5. CPU Vulnerability Matrix (Kaby Lake)

The i7-7700K (Kaby Lake, Stepping 9) shares the same Skylake microarchitecture as
the standard nodes. It has the same vulnerability surface.

| Vulnerability | CVE(s) | Status on node-gpu-01 | Notes |
|--------------|--------|------------------------|-------|
| **Meltdown** | CVE-2017-5754 | Mitigation: PTI | Page Table Isolation active |
| **Spectre v1** | CVE-2017-5753 | Mitigation: usercopy/swapgs barriers | Always active |
| **Spectre v2** | CVE-2017-5715 | Mitigation: IBRS; IBPB: conditional; STIBP: conditional; RSB filling | — |
| **Spec Store Bypass (v4)** | CVE-2018-3639 | Mitigation: SSBD via prctl | — |
| **L1TF (Foreshadow)** | CVE-2018-3615/20/46 | Mitigation: PTE Inversion; VMX: conditional cache flushes, **SMT vulnerable** | HT active |
| **MDS (Zombieload)** | CVE-2018-12126/7/30, CVE-2019-11091 | Mitigation: Clear CPU buffers; **SMT vulnerable** | HT active |
| **TAA** | CVE-2019-11135 | Mitigation: TSX disabled | TSX completely disabled |
| **SRBDS (CrossTalk)** | CVE-2020-0543 | Mitigation: Microcode | Via intel-ucode extension |
| **MMIO Stale Data** | CVE-2022-21123/5/6 | Mitigation: Clear CPU buffers; **SMT vulnerable** | HT active |
| **Retbleed** | — | Mitigation: IBRS | — |
| **Downfall (GDS)** | CVE-2022-40982 | Mitigation: Microcode | Microcode-based fix |
| **ITLB Multihit** | — | KVM: Mitigation: Split huge pages | — |
| **vmscape** | — | Mitigation: IBPB before exit to userspace | — |
| Ghostwrite | — | Not affected | — |
| Indirect Target Selection | — | Not affected | — |
| Old Microcode | — | Not affected | Microcode 0xf8 is current |
| Reg File Data Sampling | — | Not affected | — |
| Spec RStack Overflow | — | Not affected | — |
| TSA | — | Not affected | — |

**"SMT vulnerable" entries** indicate that L1TF, MDS, and MMIO Stale Data cross-thread
attack vectors remain open because Hyper-Threading is active. `nosmt` would eliminate these
but costs 20-30% throughput on a 4C CPU. Acceptable risk in an isolated homelab network
(same decision as standard nodes — see kernel-tuning.md Section 5.5).

---

## 6. Current Configuration State

### Patch Chain

```
patches/common.yaml → patches/worker-gpu.yaml → nodes/node-gpu-01.yaml
```

### Sysctls (from worker-gpu.yaml)

| Sysctl | Value | Talos Default | Purpose |
|--------|-------|---------------|---------|
| `net.core.bpf_jit_harden` | `1` | `2` | Lowers BPF JIT hardening — constant blinding only for unprivileged users |

All other sysctls are inherited from `patches/common.yaml` (see kernel-tuning.md Sections 4-5).

### Kernel Modules (from worker-gpu.yaml)

| Module | Parameters | Purpose |
|--------|------------|---------|
| nvidia | — | NVIDIA GPU kernel driver |
| nvidia_uvm | — | Unified Virtual Memory (CUDA) |
| nvidia_modeset | — | Mode-setting support |
| nvidia_drm | — | DRM integration |

DRBD modules (`drbd`, `drbd_transport_tcp`) are loaded via `patches/common.yaml`.

### Installed Extensions

| Extension | Version | Purpose |
|-----------|---------|---------|
| drbd | 9.2.16-v1.12.4 | DRBD kernel module for LINSTOR |
| i915 | 20260110-v1.12.4 | Intel iGPU driver firmware |
| intel-ice-firmware | 20260110 | Intel network firmware |
| intel-ucode | 20260210 | Intel CPU microcode updates |
| nvme-cli | v2.14 | NVMe management tools |
| nvidia-open-gpu-kernel-modules-lts | 580.126.16-v1.12.4 | NVIDIA open kernel modules |
| nvidia-container-toolkit-lts | 580.126.16-v1.18.2 | NVIDIA container runtime |

### NVIDIA Driver Status

- Driver version: 580.126.16 (Open Kernel Module)
- All 3 GPUs registered as DRM devices (minor 1, 2, 3)
- Kubernetes resource: `nvidia.com/gpu: 3` (allocatable and capacity)

### Verified Sysctl Values

Key values read from the live node — all match `patches/common.yaml` configuration:

| Category | Sysctl | Configured | Live Value | Match |
|----------|--------|------------|------------|-------|
| Storage I/O | vm.dirty_ratio | 10 | 10 | Yes |
| Storage I/O | vm.dirty_background_ratio | 5 | 5 | Yes |
| Memory | vm.overcommit_memory | 1 | 1 | Yes |
| Memory | vm.max_map_count | 524288 | 524288 | Yes |
| Memory | vm.min_free_kbytes | 65536 | 65536 | Yes |
| TCP Buffer | net.core.rmem_max | 16777216 | 16777216 | Yes |
| TCP Buffer | net.core.wmem_max | 16777216 | 16777216 | Yes |
| TCP | net.ipv4.tcp_slow_start_after_idle | 0 | 0 | Yes |
| TCP | net.ipv4.tcp_tw_reuse | 1 | 1 | Yes |
| TCP | net.ipv4.tcp_fastopen | 3 | 3 | Yes |
| TCP | net.ipv4.tcp_keepalive_time | 600 | 600 | Yes |
| Backlog | net.core.somaxconn | 32768 | 32768 | Yes |
| Backlog | net.core.netdev_max_backlog | 16384 | 16384 | Yes |
| Conntrack | net.netfilter.nf_conntrack_max | 131072 | 131072 | Yes |
| Security | net.ipv4.conf.all.rp_filter | 1 | 0 | **Cilium override** |
| Security | net.ipv4.conf.default.rp_filter | 1 | 1 | Yes |
| Security | kernel.kexec_load_disabled | 1 | 1 | Yes |
| Security | kernel.sysrq | 0 | 0 | Yes |
| BPF | net.core.bpf_jit_harden | 1 | 1 | Yes (GPU override) |
| Limits | kernel.pid_max | 4194304 | 4194304 | Yes |
| Limits | fs.inotify.max_user_watches | 524288 | 524288 | Yes |

**Note:** `net.ipv4.conf.all.rp_filter` shows `0` because Cilium's `cilium-sysctlfix`
init container overrides it on its managed interfaces. The `default` value of `1` ensures
new interfaces still get strict reverse-path filtering.

---

## 7. Boot Parameter Gap Analysis

The GPU factory schematic (`talos-factory-schematic-gpu.yaml`) defines 14 extraKernelArgs,
but **none are currently applied**. The node has not been upgraded with the schematic image.

### Configured vs Applied

| Boot Parameter | In Schematic | In /proc/cmdline | Status |
|----------------|:------------:|:----------------:|--------|
| `cpufreq.default_governor=performance` | Yes | **No** | Governor is `powersave` |
| `intel_idle.max_cstate=0` | Yes | **No** | C-States still active |
| `processor.max_cstate=0` | Yes | **No** | C-States still active |
| `transparent_hugepage=madvise` | Yes | **No** | Happens to be `madvise` anyway (kernel 6.18 default) |
| `elevator=none` | Yes | **No** | Scheduler is `mq-deadline` (better for HDD boot disk) |
| `mitigations=auto` | Yes | **No** | Mitigations active anyway (kernel default) |
| `init_on_free=1` | Yes | **No** | Not active — freed memory not zeroed |
| `page_alloc.shuffle=1` | Yes | **No** | Not active |
| `randomize_kstack_offset=on` | Yes | **No** | Not active |
| `vsyscall=none` | Yes | **No** | Not active |
| `debugfs=off` | Yes | **No** | debugfs accessible |
| `intel_iommu=on` | Yes | **No** | IOMMU active anyway (DMAR auto-detected) |
| `iommu=force` | Yes | **No** | Not enforced |
| `iommu.passthrough=0` | Yes | **No** | Not set (but domain type is Translated) |
| `iommu.strict=1` | Yes | **No** | **DMA-FQ (lazy) mode active** — strict not enforced |

### Parameters Only in /proc/cmdline (Talos defaults)

These are Talos KSPP boot parameters, always present:

| Parameter | Purpose |
|-----------|---------|
| `talos.platform=metal` | Platform identifier |
| `console=tty0` | Console output |
| `init_on_alloc=1` | Zero memory on allocation |
| `slab_nomerge` | Prevent slab cache merging |
| `pti=on` | Page Table Isolation |
| `consoleblank=0` | Disable console blanking |
| `nvme_core.io_timeout=4294967295` | NVMe infinite timeout |
| `printk.devkmsg=on` | Device kmsg output |
| `selinux=1` | SELinux enabled |
| `module.sig_enforce=1` | Module signature enforcement |

### Observable Impact

| Aspect | Expected (with schematic) | Actual (without) | Impact |
|--------|---------------------------|-------------------|--------|
| CPU Governor | performance (max freq always) | powersave (dynamic scaling) | Higher latency on burst workloads |
| CPU C-States | Disabled (always C0) | Active (deep sleep available) | Variable wake-up latency |
| Turbo Boost | Would benefit from performance governor | Disabled in BIOS regardless | **BIOS change needed separately** |
| IOMMU Mode | Strict (immediate TLB invalidation) | Lazy/DMA-FQ | Slightly less secure but better DMA performance |
| Memory Zeroing | init_on_free=1 (freed memory zeroed) | Not active | Freed memory may contain stale data |
| I/O Scheduler | none (noop) | mq-deadline | mq-deadline is actually better for the HDD |

**Action required:** Run `make upgrade-node-gpu-01` to burn the schematic's extraKernelArgs
into the UKI image. This requires a node reboot.

---

## 8. GPU-Specific Considerations

### 8.1 IOMMU: Strict vs Lazy Mode

The standard factory schematic uses `iommu.strict=1` (strict TLB invalidation). On the GPU
node, this deserves reconsideration:

**Strict mode (`iommu.strict=1`):**
- Every DMA unmap triggers an immediate IOTLB invalidation
- Higher security — prevents stale TLB entries from being exploited
- Measurable overhead with 3 GPUs doing heavy DMA operations (CUDA memory transfers)

**Lazy mode (`iommu.strict=0`, DMA-FQ):**
- Batches IOTLB invalidations using a flush queue
- Significantly lower overhead for DMA-heavy workloads
- The kernel currently defaults to this mode on node-gpu-01
- Acceptable security trade-off: the GPUs are trusted devices, not hotplugged

**Recommendation:** Use `iommu.strict=0` in the GPU schematic. The 3 NVIDIA GPUs perform
thousands of DMA operations per second during compute workloads. Strict mode adds measurable
latency per operation. In a homelab with trusted PCIe devices, lazy mode is the correct
trade-off.

### 8.2 PCIe ASPM (Active State Power Management)

The BTC B250C is a mining motherboard. Mining boards are known for:
- Unreliable ASPM implementation (power management not a priority in mining)
- Multiple PCIe slots running at x1 via risers (ASPM can cause link instability)
- Non-standard PCIe power delivery

**Recommendation:** Add `pcie_aspm=off` to the GPU schematic. ASPM saves negligible power
on a system with 3 GPUs (~5W TDP each GPU in idle) while risking PCIe link instability.
Standard practice for multi-GPU systems.

### 8.3 NVIDIA Kernel Module Parameters

The NVIDIA open kernel module supports several tuning parameters:

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `NVreg_UsePageAttributeTable=1` | Enable PAT | Improved GPU memory caching via x86 Page Attribute Table. NVIDIA-recommended for Linux. Better write-combining for framebuffer access. |

This can be set either via:
- Boot parameter: `nvidia.NVreg_UsePageAttributeTable=1` (in schematic)
- Module parameter in `worker-gpu.yaml` under `machine.kernel.modules`

The module parameter approach is preferred — it's specific to the GPU role patch and doesn't
pollute the schematic.

### 8.4 Turbo Boost (BIOS)

NFD reports `cpu-pstate.turbo=false`. The i7-7700K supports Turbo Boost to 4.5 GHz (base
4.2 GHz). Turbo Boost is disabled in the BTC B250C BIOS.

**Recommendation:** Enable Turbo Boost in BIOS. Free 7% single-core performance increase
with no configuration changes needed. The `performance` governor (once applied via schematic
upgrade) will keep the CPU at max frequency, and Turbo Boost allows it to reach 4.5 GHz.

### 8.5 bpf_jit_harden Override

`patches/worker-gpu.yaml` sets `net.core.bpf_jit_harden: "1"`, lowering the Talos default
from `2` to `1`:

- **Value 2** (Talos default): Constant blinding for ALL users, including root
- **Value 1** (GPU override): Constant blinding only for unprivileged users

Cilium runs as privileged DaemonSet (root + all capabilities), so both values are compatible.
The override was likely set to reduce BPF JIT compilation overhead, but the performance
impact of value `2` is negligible (nanoseconds per BPF program load).

**Recommendation:** Remove the override and restore the Talos default (`2`). See
kernel-tuning.md Section 7 for full analysis.

---

## 9. Recommendations

### 9.1 Immediate: Schematic Changes (talos-factory-schematic-gpu.yaml)

| Change | Current | Recommended | Rationale |
|--------|---------|-------------|-----------|
| `iommu.strict` | `1` | `0` | Lazy mode (DMA-FQ) for 3 GPU DMA-heavy workloads. Trusted devices in homelab. |
| Add `pcie_aspm=off` | not set | `pcie_aspm=off` | Mining board has unreliable ASPM. Standard multi-GPU practice. |
| Add `nvidia.NVreg_UsePageAttributeTable=1` | not set | add to extraKernelArgs **or** module params | Better GPU memory caching. |

### 9.2 Immediate: Config Changes (worker-gpu.yaml)

| Change | Current | Recommended | Rationale |
|--------|---------|-------------|-----------|
| Remove `bpf_jit_harden: "1"` | `1` | Remove (Talos default `2`) | Security improvement, negligible performance impact |
| Add NVIDIA module params | none | `NVreg_UsePageAttributeTable=1` | If not added to schematic boot params |

### 9.3 Immediate: Apply Schematic (upgrade)

Run `make upgrade-node-gpu-01` to apply the factory schematic boot parameters. The node has
**never** been upgraded with the GPU schematic — all 14 extraKernelArgs are not applied.

### 9.4 BIOS Changes (manual, requires physical access)

| Setting | Current | Recommended | Rationale |
|---------|---------|-------------|-----------|
| Intel Turbo Boost | Disabled | **Enable** | Free 7% performance (4.2→4.5 GHz) |
| PCIe ASPM | Unknown | **Disable** (if option exists) | Belt-and-suspenders with `pcie_aspm=off` boot param |
| VT-d | Enabled | Keep enabled | IOMMU already active and working |

### 9.5 Not Recommended for GPU Node

| Parameter | Why Not |
|-----------|---------|
| `nosmt` | 4C→4T on i7-7700K = 50% thread loss. Cross-thread attacks require local privilege. |
| `iommu.strict=1` | Too much DMA overhead with 3 GPUs. See Section 8.1. |
| `lockdown=integrity` | Would block NVIDIA out-of-tree modules. |
| `kernel.modules_disabled=1` | NVIDIA and DRBD modules loaded dynamically. |

---

## 10. Verification

After applying schematic upgrade and config changes:

```bash
# Verify boot parameters are applied
talosctl -n 192.168.2.67 -e 192.168.2.67 read /proc/cmdline
# Should contain: cpufreq.default_governor=performance intel_idle.max_cstate=0 etc.

# CPU governor (should be "performance")
talosctl -n 192.168.2.67 -e 192.168.2.67 read /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# C-States disabled (max_cstate=0)
talosctl -n 192.168.2.67 -e 192.168.2.67 dmesg | grep -i "intel_idle"

# IOMMU mode (should show DMA-FQ/lazy after iommu.strict=0)
talosctl -n 192.168.2.67 -e 192.168.2.67 dmesg | grep -i "iommu.*policy"

# PCIe ASPM disabled
talosctl -n 192.168.2.67 -e 192.168.2.67 dmesg | grep -i "aspm"

# NVIDIA PAT enabled
talosctl -n 192.168.2.67 -e 192.168.2.67 dmesg | grep -i "PAT"

# GPU status
talosctl -n 192.168.2.67 -e 192.168.2.67 dmesg | grep -i "nvidia"

# BPF JIT harden (should be 2 after removing override)
talosctl -n 192.168.2.67 -e 192.168.2.67 read /proc/sys/net/core/bpf_jit_harden

# I/O scheduler on boot disk
talosctl -n 192.168.2.67 -e 192.168.2.67 read /sys/block/sda/queue/scheduler

# CPU vulnerabilities
for v in gather_data_sampling l1tf mds meltdown spectre_v1 spectre_v2 srbds; do
  echo -n "$v: "
  talosctl -n 192.168.2.67 -e 192.168.2.67 read /sys/devices/system/cpu/vulnerabilities/$v
done

# Turbo Boost (after BIOS change)
talosctl -n 192.168.2.67 -e 192.168.2.67 read /sys/devices/system/cpu/intel_pstate/no_turbo
# Should be 0 (turbo enabled)
```

---

## 11. Sources

### Hardware
- [BTC B250C specifications](https://www.biostar.com.tw/app/en/mb/introduction.php?S_ID=895) — Mining motherboard datasheet
- [Intel i7-7700K specifications](https://ark.intel.com/content/www/us/en/ark/products/97129/intel-core-i7-7700k-processor-8m-cache-up-to-4-50-ghz.html) — Kaby Lake, 4C/8T, 4.2-4.5 GHz
- [Intel B250 Chipset](https://ark.intel.com/content/www/us/en/ark/products/98420/intel-b250-chipset.html) — PCIe 3.0, VT-d support

### NVIDIA / GPU
- [NVIDIA Open GPU Kernel Modules](https://github.com/NVIDIA/open-gpu-kernel-modules) — Open-source kernel driver
- [NVIDIA Linux Driver README — Module Parameters](https://download.nvidia.com/XFree86/Linux-x86_64/580.126.16/README/openrmkernel.html) — NVreg_UsePageAttributeTable documentation
- [NVIDIA GA104 (Ampere)](https://www.techpowerup.com/gpu-specs/nvidia-ga104.g906) — GPU die specifications

### IOMMU / PCIe
- [Linux IOMMU Documentation](https://docs.kernel.org/driver-api/iommu.html) — strict vs lazy mode
- [PCIe ASPM on multi-GPU systems](https://wiki.archlinux.org/title/Power_management#PCI_Runtime_Power_Management) — ASPM disable rationale
- [VFIO / IOMMU Groups](https://docs.kernel.org/driver-api/vfio.html) — PCI device grouping

### Talos / Kernel (shared with kernel-tuning.md)
- [Talos KSPP Source Code (kspp.go)](https://github.com/siderolabs/talos/blob/main/pkg/kernel/kspp/kspp.go)
- [Talos Kernel Reference](https://docs.siderolabs.com/talos/v1.12/reference/kernel)
- [Linux Kernel VM Documentation](https://docs.kernel.org/admin-guide/sysctl/vm.html)
- [Linux Spectre Documentation](https://docs.kernel.org/admin-guide/hw-vuln/spectre.html)
