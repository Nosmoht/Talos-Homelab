---
name: gitops-health-triage
description: Triage ArgoCD app sync/health drift and produce a focused remediation plan with safe GitOps-first actions for this homelab repository.
argument-hint: [application-name|all]
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, Write
---

# GitOps Health Triage

Use this skill when ArgoCD applications are OutOfSync, Degraded, or repeatedly failing to reconcile.

## Inputs
- Argument: one application name (`dex`, `kube-prometheus-stack`) or `all`.
- Kubeconfig default: `/tmp/homelab-kubeconfig`.

## Workflow

### 1. Gather status quickly
Run:
```bash
KUBECONFIG=/tmp/homelab-kubeconfig kubectl -n argocd get applications
```
If a specific app is provided, also run:
```bash
KUBECONFIG=/tmp/homelab-kubeconfig kubectl -n argocd get application <app> -o yaml
KUBECONFIG=/tmp/homelab-kubeconfig kubectl -n argocd describe application <app>
```

### 2. Classify failure mode
Classify into one of:
- webhook/defaulted-field drift
- immutable field/selector patch rejection
- missing CRD/order dependency
- Cilium network policy blocking hooks or control-plane traffic
- stale operation state / exhausted retries

### 3. Map to repository paths
Identify manifests driving the app:
- app CR: `kubernetes/overlays/homelab/infrastructure/<component>/application.yaml`
- additional resources: `.../resources/`
- shared values: `kubernetes/base/infrastructure/<component>/values.yaml`
- overlay values: `kubernetes/overlays/homelab/infrastructure/<component>/values.yaml`

### 4. Propose GitOps-safe remediation
Always prefer a git change first. Only propose direct cluster actions when necessary to unblock controller state.

## Output
Write `docs/argocd-triage-<app-or-all>-<yyyy-mm-dd>.md` with:
1. Current state summary
2. Root cause hypothesis + confidence
3. Exact files to modify
4. Verification commands
5. Emergency-only live actions (if any)

## Hard Rules
- Do not deploy with `kubectl apply` for ArgoCD-managed resources.
- When suggesting live patches (e.g., clear operation state), include the follow-up git change required to make state convergent.
