---
name: cilium-policy-debug
description: Diagnose Cilium and Gateway API traffic drops, map failures to CiliumNetworkPolicy manifests, and propose least-privilege fixes.
argument-hint: [namespace/app-or-flow]
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, Write
---

# Cilium Policy Debug

Use this skill when traffic fails between Gateway/API, monitoring components, or intra-cluster services.

## Inputs
- Optional scope argument (`monitoring/prometheus`, `dex/postgresql`, `gateway-api`).

## Workflow

### 1. Gather live signals
Run (as available):
```bash
KUBECONFIG=/tmp/homelab-kubeconfig kubectl get cnp -A
KUBECONFIG=/tmp/homelab-kubeconfig kubectl get pods -A -o wide
KUBECONFIG=/tmp/homelab-kubeconfig kubectl -n kube-system get pods -l k8s-app=cilium
```
If hubble is available, use it for drop evidence (`hubble observe`).

### 2. Determine policy mismatch
Check common failure classes:
- wrong entity (`world` vs `ingress` for Gateway API)
- wrong API-server egress port (`443` vs post-DNAT `6443`)
- hook/job labels not covered by endpointSelector
- conflicting K8s NetworkPolicy + CiliumNetworkPolicy AND semantics

### 3. Map to Git manifests
Primary locations:
- `kubernetes/overlays/homelab/infrastructure/**/resources/cnp-*.yaml`
- `kubernetes/bootstrap/cilium/cilium.yaml`

### 4. Produce least-privilege patch proposal
Recommend narrow selectors and ports only. Avoid broad allow-all policies.

## Output
Write `docs/cilium-debug-<scope>-<yyyy-mm-dd>.md` including:
1. evidence (drops, denied flows, affected identities)
2. root cause
3. manifest file(s) to patch
4. exact validation commands

## Hard Rules
- Do not propose wildcard policies unless justified as temporary incident mitigation.
- Include a follow-up hardening step when temporary broadening is used.
