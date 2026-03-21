---
name: pre-drain-storage-check
description: Validate DRBD replication health and safely drain a node before Talos upgrade or maintenance, preventing CSI unmount deadlocks that require physical power cycle.
argument-hint: <node-name>
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, Write
---

# Pre-Drain Storage Check

Use this skill to validate DRBD replication health and safely drain a Kubernetes node before a Talos upgrade or maintenance window. This prevents CSI unmount deadlocks where DRBD volumes enter D-state during the `unmountPodMounts` phase, locking the upgrade sequence with no API recovery — only fixable with a physical power cycle.

This skill can be used standalone or as the drain step within `execute-talos-upgrade`. The `execute-talos-upgrade` skill should reference this skill for its drain phase rather than implementing drain logic independently.

## Inputs
- Required: `node-name` — the short node name (e.g. `node-04`, `node-gpu-01`, `node-pi-01`)

Examples:
```text
pre-drain-storage-check node-04
pre-drain-storage-check node-gpu-01
pre-drain-storage-check node-pi-01
```

## Cluster Context
- LINSTOR/Piraeus Operator CSI in `piraeus-datastore` namespace, DRBD replication, NVMe-backed nodes
- DRBD satellite mesh uses port range 7000-7999
- Stuck "shutting down" nodes (D-state on DRBD) are only fixable with physical power cycle
- CSI unmount deadlock risk: DRBD CSI volumes in D-state during `unmountPodMounts` phase deadlock the upgrade with no API recovery — `talosctl reboot`, `upgrade --force`, and `reset` all fail with "locked"
- Node inventory: node-01..03 (control plane), node-04..06 (workers), node-gpu-01 (GPU worker), node-pi-01 (Pi worker)
- Network: 192.168.2.0/24

## Workflow

### 1. Resolve node name to IP
Read the node definition file at `talos/nodes/<node-name>.yaml` and extract the node IP address from the file content.

```bash
# Example: read the node file to find the IP
cat talos/nodes/<node-name>.yaml
```

Parse the IP from the YAML (look for the node's address field). Record both the node name and IP for use in subsequent steps.

If the file does not exist, stop and report the error — do not guess the IP.

### 2. Gate: no faulty DRBD resources cluster-wide
Run the faulty resource check:

```bash
kubectl linstor resource list --faulty
```

If the output contains any faulty resources, **stop immediately**. Report the faulty resources and do not proceed with the drain. Faulty resources before drain indicate pre-existing replication problems that must be resolved first.

### 3. Enumerate DRBD resources on target node
List all DRBD resources assigned to the target node:

```bash
kubectl linstor resource list --nodes <node-name>
```

Record every resource name and its replication state. If the node has no DRBD resources, proceed to step 5 but note that the replica health gate (step 4) was skipped. Step 5 will still identify any piraeus-csi PVCs on the node; if found, warn the operator that CSI unmount risk exists even without local DRBD replicas.

### 4. Gate: every resource has >= 1 UpToDate replica on another node
For each DRBD resource found on the target node in step 3, verify that at least one other node holds an `UpToDate` replica of that resource.

```bash
kubectl linstor resource list --resources <resource-name>
```

Check the output for each resource:
- The target node's replica state does not matter for this gate.
- At least one replica on a **different** node must be `UpToDate`.
- If any resource has zero UpToDate replicas on other nodes, **stop immediately**. Draining would risk data loss for that resource.

Report which resources passed and which failed the replica gate.

### 5. Find pods with piraeus-csi PVCs on target node
Identify pods on the target node that use PersistentVolumeClaims backed by the piraeus-csi StorageClass:

```bash
# List pods on the target node
kubectl get pods --all-namespaces --field-selector spec.nodeName=<node-name> -o wide

# List PVCs and their storage classes to cross-reference
kubectl get pvc --all-namespaces -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STORAGECLASS:.spec.storageClassName,VOLUME:.spec.volumeName'
```

Record which pods on the target node are attached to piraeus-csi volumes. These are the pods most at risk of CSI unmount deadlock during drain.

### 6. Execute kubectl drain
Drain the node with the standard safety flags:

```bash
kubectl drain <node-name> --delete-emptydir-data --ignore-daemonsets --timeout=120s
```

Monitor the drain output. If the drain times out or fails:
- Check which pods are stuck evicting
- Check if DRBD resources have entered a degraded state
- Report the failure and do not proceed — a stuck drain is the early warning for the exact deadlock this skill exists to prevent

### 7. Post-drain: verify no new faulty resources
After a successful drain, re-run the faulty resource check:

```bash
kubectl linstor resource list --faulty
```

If new faulty resources appeared after the drain, report them as a warning. The drain succeeded but DRBD replication may need attention before proceeding with maintenance.

Also verify the node is in `SchedulingDisabled` state:

```bash
kubectl get node <node-name>
```

### 8. Write output report
Save the results to `docs/pre-drain-check-<node-name>-<yyyy-mm-dd>.md` with the following structure:

```markdown
---
skill: pre-drain-storage-check
node: <node-name>
node_ip: <node-ip>
date: <yyyy-mm-dd>
result: pass | fail
---

# Pre-Drain Storage Check: <node-name>

## Faulty Resource Gate (Pre-Drain)
<result of step 2>

## DRBD Resources on Node
<table or list from step 3>

## Replica Health Gate
<per-resource result from step 4>

## Piraeus-CSI Pods on Node
<list from step 5>

## Drain Result
<output summary from step 6>

## Post-Drain Faulty Resource Check
<result of step 7>

## Node Status
<SchedulingDisabled confirmation>
```

## Failure Modes
- **Node file not found**: Stop. Do not guess IPs.
- **Faulty resources pre-drain**: Stop. Report faulty resources and require manual remediation before retrying.
- **Single-replica resource with no UpToDate peer**: Stop. Draining would risk data loss.
- **Drain timeout**: Stop. Report stuck pods. Do not force-drain — this is the early warning for CSI unmount deadlock.
- **kubectl or linstor CLI unavailable**: Stop. These tools are required.
- **Post-drain faulty resources**: Warn but do not undo the drain. The node is already cordoned; report the issue for operator attention.

## Output Format
Write the report file first, then present a concise summary in chat including:
- the saved report path
- whether all gates passed
- which DRBD resources were on the node and their replica status
- whether the drain completed successfully
- any warnings or issues requiring attention before proceeding with maintenance
