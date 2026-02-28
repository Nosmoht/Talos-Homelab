---
name: analyze-node-hardware
description: Analyze hardware of a Talos node using talosctl and NFD. Produces comprehensive hardware profile for kernel tuning.
argument-hint: [node-name-or-ip]
disable-model-invocation: true
allowed-tools: Bash, Read, Glob, Grep, Write
---

# Analyze Node Hardware

Comprehensive hardware analysis of a Talos Kubernetes node. Gathers data via `talosctl` and `kubectl` NFD (Node Feature Discovery), reads current config state, and produces a structured hardware profile document.

## Argument Resolution

The user provides either a node name (e.g., `node-gpu-01`) or an IP address (e.g., `192.168.2.67`).

1. If given a **node name**: look up `nodes/<name>.yaml` to find the IP address (under `machine.network.interfaces[].addresses`).
2. If given an **IP address**: scan `nodes/*.yaml` files to find the matching node name by IP, and read the HostnameConfig `hostname` field.
3. If neither matches, ask the user for clarification.

Store both `NODE_NAME` and `NODE_IP` for use throughout.

## Data Gathering

### Step 1: Hardware Data via talosctl

Run the following commands (parallelize where possible). All talosctl commands MUST use explicit endpoint: `talosctl -n $NODE_IP -e $NODE_IP`.

```bash
# CPU info
talosctl -n $NODE_IP -e $NODE_IP read /proc/cpuinfo

# Memory info
talosctl -n $NODE_IP -e $NODE_IP read /proc/meminfo

# DMI / system identification
talosctl -n $NODE_IP -e $NODE_IP read /sys/devices/virtual/dmi/id/product_name
talosctl -n $NODE_IP -e $NODE_IP read /sys/devices/virtual/dmi/id/board_name
talosctl -n $NODE_IP -e $NODE_IP read /sys/devices/virtual/dmi/id/sys_vendor

# Current boot parameters
talosctl -n $NODE_IP -e $NODE_IP read /proc/cmdline

# CPU vulnerability mitigations
for v in $(talosctl -n $NODE_IP -e $NODE_IP ls /sys/devices/system/cpu/vulnerabilities/ 2>/dev/null | tail -n +2 | awk '{print $NF}'); do
  echo -n "$v: "
  talosctl -n $NODE_IP -e $NODE_IP read /sys/devices/system/cpu/vulnerabilities/$v 2>/dev/null
done

# CPU frequency governor
talosctl -n $NODE_IP -e $NODE_IP read /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
talosctl -n $NODE_IP -e $NODE_IP read /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors 2>/dev/null

# Turbo boost status
talosctl -n $NODE_IP -e $NODE_IP read /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null

# THP status
talosctl -n $NODE_IP -e $NODE_IP read /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null

# NUMA status
talosctl -n $NODE_IP -e $NODE_IP ls /sys/devices/system/node/ 2>/dev/null

# Block devices — list /sys/block/ then for each real device read scheduler and rotational
talosctl -n $NODE_IP -e $NODE_IP ls /sys/block/
# For each device (sda, sdb, nvme0n1, etc.):
talosctl -n $NODE_IP -e $NODE_IP read /sys/block/$DEV/queue/scheduler
talosctl -n $NODE_IP -e $NODE_IP read /sys/block/$DEV/queue/rotational

# IOMMU status
talosctl -n $NODE_IP -e $NODE_IP dmesg | grep -iE "(iommu|dmar|vt-d)"

# NVIDIA / GPU info (if applicable)
talosctl -n $NODE_IP -e $NODE_IP dmesg | grep -iE "(nvidia|gpu|drm)"

# Network interfaces
talosctl -n $NODE_IP -e $NODE_IP read /proc/net/dev

# Loaded modules (via dmesg or /proc/modules if accessible)
talosctl -n $NODE_IP -e $NODE_IP dmesg | grep -iE "module.*loaded|driver.*registered"

# PCI devices — list all and identify by reading vendor/device/class
talosctl -n $NODE_IP -e $NODE_IP ls /sys/bus/pci/devices/
# For key devices, read:
talosctl -n $NODE_IP -e $NODE_IP read /sys/bus/pci/devices/$BDF/vendor
talosctl -n $NODE_IP -e $NODE_IP read /sys/bus/pci/devices/$BDF/device
talosctl -n $NODE_IP -e $NODE_IP read /sys/bus/pci/devices/$BDF/class

# Installed Talos extensions
talosctl -n $NODE_IP -e $NODE_IP get extensions
```

### Step 2: NFD Data via kubectl

```bash
# Node labels (includes NFD feature labels)
kubectl get node $NODE_NAME -o yaml

# Full NFD feature discovery (if NFD is deployed)
kubectl get nodefeature -n node-feature-discovery $NODE_NAME -o yaml 2>/dev/null
```

### Step 3: Current Config State

Read the following files to understand what's currently configured:

1. `patches/common.yaml` — shared sysctls and settings for all nodes
2. Determine the node's role from its Kubernetes labels (`node-role.kubernetes.io/control-plane` or worker):
   - Control plane: `patches/controlplane.yaml`
   - GPU worker: `patches/worker-gpu.yaml`
   - Standard workers have no role patch (install image injected dynamically via Makefile)
3. `nodes/$NODE_NAME.yaml` — node-specific config
4. Determine the correct factory schematic:
   - Standard nodes: `talos-factory-schematic.yaml`
   - GPU worker: `talos-factory-schematic-gpu.yaml`
   - Check the `machine.install.image` URL in the role patch — the schematic ID in the URL identifies which schematic file

### Step 4: Live Sysctl Verification

Read key sysctl values from the live node and compare against configured values:

```bash
# Storage I/O
talosctl -n $NODE_IP -e $NODE_IP read /proc/sys/vm/dirty_ratio
talosctl -n $NODE_IP -e $NODE_IP read /proc/sys/vm/dirty_background_ratio

# Memory
talosctl -n $NODE_IP -e $NODE_IP read /proc/sys/vm/overcommit_memory
talosctl -n $NODE_IP -e $NODE_IP read /proc/sys/vm/max_map_count
talosctl -n $NODE_IP -e $NODE_IP read /proc/sys/vm/min_free_kbytes

# Network buffers
talosctl -n $NODE_IP -e $NODE_IP read /proc/sys/net/core/rmem_max
talosctl -n $NODE_IP -e $NODE_IP read /proc/sys/net/core/wmem_max
talosctl -n $NODE_IP -e $NODE_IP read /proc/sys/net/core/somaxconn
talosctl -n $NODE_IP -e $NODE_IP read /proc/sys/net/core/netdev_max_backlog

# TCP
talosctl -n $NODE_IP -e $NODE_IP read /proc/sys/net/ipv4/tcp_slow_start_after_idle
talosctl -n $NODE_IP -e $NODE_IP read /proc/sys/net/ipv4/tcp_congestion_control

# Security
talosctl -n $NODE_IP -e $NODE_IP read /proc/sys/net/core/bpf_jit_harden
talosctl -n $NODE_IP -e $NODE_IP read /proc/sys/kernel/kexec_load_disabled
talosctl -n $NODE_IP -e $NODE_IP read /proc/sys/net/ipv4/conf/all/rp_filter

# Conntrack
talosctl -n $NODE_IP -e $NODE_IP read /proc/sys/net/netfilter/nf_conntrack_max

# Process limits
talosctl -n $NODE_IP -e $NODE_IP read /proc/sys/kernel/pid_max
talosctl -n $NODE_IP -e $NODE_IP read /proc/sys/fs/inotify/max_user_watches
```

## Output Document

Write the analysis to `docs/hardware-analysis-$NODE_NAME.md` with the following structure:

```markdown
# Hardware Analysis: $NODE_NAME

> **Date:** YYYY-MM-DD
> **Talos:** version | **Kubernetes:** version
> **Node IP:** $NODE_IP | **Role:** control-plane/worker

---

## 1. System Overview

| Property | Value |
|----------|-------|
| Board | ... |
| Vendor | ... |
| CPU | ... |
| Cores/Threads | ... |
| RAM | ... |
| Boot Disk | ... |
| Data Disk | ... |
| Active NIC | ... |
| GPUs | ... (if any) |

## 2. PCI Device Inventory

Table with BDF, Vendor:Device, Class, Description

## 3. USB Device Inventory

Table with Vendor:Device, Class, Serial, Description (from NFD usb.device)

## 4. NFD Feature Highlights

Key NFD features organized by category (CPU, Storage, Memory, PCI, USB)

## 5. CPU Vulnerability Status

Table: Vulnerability | CVE | Status (from /sys/devices/system/cpu/vulnerabilities/*)

## 6. Current Kernel Parameters

### 6.1 Boot Parameters (/proc/cmdline)
Parsed list of current boot parameters

### 6.2 Configured Boot Parameters (from schematic)
What the factory schematic specifies in extraKernelArgs

### 6.3 Gap Analysis
Table showing: Parameter | In Schematic | In /proc/cmdline | Status

### 6.4 Sysctl Verification
Table: Sysctl | Configured Value | Live Value | Match (yes/no)

## 7. Storage Profile

Table: Device | Type | Scheduler | Rotational | Role

## 8. Network Profile

Table: Interface | Driver | Type | Speed | Status

## 9. GPU Profile (if applicable)

Driver version, IOMMU groups, PCIe topology, Kubernetes GPU resources

## 10. Installed Extensions

Table: Extension | Version | Purpose

## 11. Observations

Bullet points of notable findings, anomalies, or recommendations for further investigation
```

## Important Notes

- Always use explicit endpoint (`-e $NODE_IP`) with talosctl — VIP forwarding does not support all operations.
- Some reads may fail (e.g., no NVMe on a node, no GPU driver). Handle gracefully — note "not present" in the output.
- The kubeconfig is at `/tmp/homelab-kubeconfig`. If `kubectl` fails, try: `KUBECONFIG=/tmp/homelab-kubeconfig kubectl ...`
- NFD namespace is `node-feature-discovery`.
- Do NOT make any changes to config files — this skill is read-only analysis.
- Write all output in English.
