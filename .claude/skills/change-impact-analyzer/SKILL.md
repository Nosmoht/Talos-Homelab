---
name: change-impact-analyzer
description: Analyze git diff or file changes to trace impact across Talos patches, Kyverno policies, CiliumNetworkPolicies, ArgoCD applications, and Helm values, reporting severity per affected component.
argument-hint: [path-or-git-diff]
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob
---

# Change Impact Analyzer

Use this skill as a pre-commit check to deterministically trace how changed files propagate through the cluster stack and report per-component severity.

## Inputs
- Optional argument: a file path (diff that path), or empty (use `git diff` for staged + unstaged).
- For branch comparison, pass `branch` to use `git diff main...HEAD`.

## Workflow

### 1. Parse changes

Determine the diff source based on the argument:

```bash
# No argument — staged + unstaged
git diff HEAD

# Argument is "branch" — full branch comparison
git diff main...HEAD

# Argument is a path — diff that specific path
git diff HEAD -- <path>
```

Collect the list of changed files and classify each into one or more categories below.

### 2. Classify each changed file and trace impact

#### Talos patch (`talos/patches/*.yaml`, `talos/nodes/*.yaml`)

| File pattern | Nodes affected |
|---|---|
| `common.yaml` | All nodes (node-01..06, node-gpu-01, node-pi-01) |
| `controlplane.yaml` | Control plane only (node-01..03) |
| `worker.yaml` | Standard workers (node-04..06) |
| `worker-gpu.yaml` | GPU worker (node-gpu-01) |
| `worker-pi.yaml` | Pi worker (node-pi-01) |
| `talos/nodes/<name>.yaml` | Single node |

Determine operation severity:
- **HIGH — Reboot required**: changes to `install` block, `machine.install`, kernel args (`machine.install.extraKernelArgs`), disk config, sysctls under `machine.sysctls`, extensions list.
- **HIGH — Schematic regeneration**: changes to system extensions require `make -C talos gen-schematics` before config gen.
- **MEDIUM — Live-apply possible**: changes to `machine.network`, `machine.time`, `machine.registries`, cluster-level fields (scheduler extraArgs, proxy, etcd).
- **LOW — Config regen only**: comment changes, annotation changes.

Always check:
- Does the change touch `extraManifests` in `controlplane.yaml`? If yes, flag Cilium reconciliation via `make -C talos upgrade-k8s`.
- Requires `make -C talos gen-configs` + `make -C talos validate-generated`.

#### Kyverno policy (`kubernetes/**/clusterpolicy*.yaml`)

Read the changed policy file and extract:
- `spec.validationFailureAction` (Enforce vs Audit)
- `spec.rules[*].match` — which namespaces, kinds, and labels are targeted
- Policy type: `validate`, `mutate`, or `generate`

Impact assessment:
- **HIGH**: Enforce-mode validation policies that match existing workloads — could block deployments.
- **MEDIUM**: Mutate policies — silently change resources on admission.
- **LOW**: Audit-mode policies or policies targeting only new resources.

Grep the cluster manifests to list workloads that match the selector:
```bash
grep -r '<matched-label-or-kind>' kubernetes/overlays/homelab/
```

#### CiliumNetworkPolicy / CiliumClusterwideNetworkPolicy (`**/cnp-*.yaml`, `**/ccnp-*.yaml`, `**/cilium-networkpolicy*.yaml`)

Read the changed CNP and extract:
- `endpointSelector` — which pods are affected
- Ingress/egress rules — which traffic flows change
- `fromEntities` / `toEntities` usage

Impact assessment:
- **HIGH**: New deny-by-default on a namespace with existing workloads, or removal of an allow rule.
- **HIGH**: Changes affecting Prometheus scraping (ports 9090, 9093, 9094, 9100, 8080, 10250, 10259).
- **MEDIUM**: Adding new allow rules (broadening access).
- **MEDIUM**: Cross-namespace impact (rules referencing other namespaces).
- **LOW**: Tightening rules on unused or new namespaces.

Check for PNI CCNP overlap:
```bash
grep -r 'platform.io/network-interface-version' kubernetes/overlays/homelab/infrastructure/
```

#### ArgoCD Application (`kubernetes/**/application.yaml`)

Read the changed Application and extract:
- `metadata.annotations["argocd.argoproj.io/sync-wave"]` — ordering
- `spec.project` — which AppProject governs it
- `spec.source.path` or `spec.source.chart` — what it deploys
- `spec.destination.namespace`

Impact assessment:
- **HIGH**: Sync-wave changes that reorder infrastructure dependencies.
- **HIGH**: Project changes (may lose permissions).
- **MEDIUM**: Source path or chart version changes.
- **LOW**: Annotation or label-only changes.

Check AppProject permissions:
```bash
grep -A 20 'spec:' kubernetes/overlays/homelab/infrastructure/<project>/application.yaml
```

#### Helm values (`kubernetes/**/values.yaml`)

Identify the Helm chart by reading the corresponding `application.yaml` or `kustomization.yaml` in the same directory tree.

Impact assessment:
- **HIGH — Immutable field risk**: Changes to `selector`, `matchLabels`, `serviceName` on Deployments/StatefulSets. These require resource deletion before apply.
- **HIGH — CRD changes**: New CRDs may need AppProject `clusterResourceWhitelist` updates.
- **MEDIUM**: Resource limits, replica counts, image versions.
- **LOW**: Annotations, labels, dashboard configs.

#### Kustomization (`kubernetes/**/kustomization.yaml`)

Diff the resource list:
- **New resources added**: Check if corresponding files exist and are valid.
- **Resources removed**: Flag that ArgoCD may need pruning enabled, or resources will be orphaned.
- **Patch changes**: Trace which base resources are affected.

Impact assessment:
- **HIGH**: Resource removal (potential data loss if PVCs or StatefulSets).
- **MEDIUM**: New resource addition.
- **LOW**: Patch or label changes.

### 3. Report impact summary

Print an inline report grouped by severity. Format:

```
## Change Impact Analysis

### HIGH severity
- [component] file: description of impact
  Action required: ...

### MEDIUM severity
- [component] file: description of impact
  Action required: ...

### LOW severity
- [component] file: description of impact

### Required actions before apply
1. ...
2. ...
```

## Cluster Context
- 3 control plane nodes (node-01..03), 3 standard workers (node-04..06), 1 GPU worker (node-gpu-01), 1 Pi worker (node-pi-01)
- ArgoCD app-of-apps pattern, sync-waves: projects(-1), infrastructure(0), apps(1-3)
- Cilium deployed via Talos extraManifests (controlplane.yaml)
- DRBD/LINSTOR storage (piraeus-datastore namespace)
- PNI for cross-namespace platform connectivity

## Hard Rules
- Do not write any output files — this is an inline-only pre-commit check.
- Do not execute `kubectl apply` or any cluster-mutating commands.
- Do not skip unrecognized file types — report them under LOW as "unclassified change".
- When multiple categories apply to a single file, report under the highest severity.
