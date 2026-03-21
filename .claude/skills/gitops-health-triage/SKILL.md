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

### 5. Execute recovery (with user confirmation)

After triage classification, if the user confirms, execute the matching recovery action:

**Exhausted retries at stale revision:**
ArgoCD auto-sync locks to the git revision at the time it started. Pushing fixes won't help until retries exhaust. Recovery:
```bash
KUBECONFIG=/tmp/homelab-kubeconfig kubectl -n argocd delete pod -l app.kubernetes.io/component=application-controller
```
This forces re-resolution of branch HEAD. Wait for the controller pod to restart, then verify the application picks up the latest revision.

**Stuck operationState:**
When hook Jobs complete and are deleted before ArgoCD observes completion, or when retries are exhausted for a fixed revision, the operationState gets stuck. Recovery:
```bash
KUBECONFIG=/tmp/homelab-kubeconfig kubectl -n argocd patch application <app> --type=json -p='[{"op":"remove","path":"/status/operationState"}]'
KUBECONFIG=/tmp/homelab-kubeconfig kubectl annotate application <app> -n argocd argocd.argoproj.io/refresh=hard --overwrite
```

**Hook job unobserved completion:**
Same pattern as stuck operationState — clear the state and force a hard refresh.

**Immutable selector conflict:**
When a Helm chart upgrade changes `spec.selector.matchLabels` on a Deployment or StatefulSet, Kubernetes rejects the update. Recovery (requires explicit user confirmation before each delete):
1. Identify the Deployment/Service with the immutable selector
2. `KUBECONFIG=/tmp/homelab-kubeconfig kubectl delete deployment <name> -n <ns>` (and Service if selector changed)
3. Force ArgoCD resync: `KUBECONFIG=/tmp/homelab-kubeconfig kubectl annotate application <app> -n argocd argocd.argoproj.io/refresh=hard --overwrite`
4. Also check Service selector for stale labels from three-way merge

**Important recovery rules:**
- Always ask for user confirmation before executing any recovery action
- After any live recovery action, identify the corresponding git change needed to prevent recurrence
- Never delete StatefulSets or PVCs as part of recovery without explicit user approval
- Log all recovery actions taken in the output report

## Output
Write `docs/argocd-triage-<app-or-all>-<yyyy-mm-dd>.md` with:
1. Current state summary
2. Root cause hypothesis + confidence
3. Exact files to modify
4. Verification commands
5. Emergency-only live actions (if any)
6. Recovery actions taken (if any)
7. Follow-up git changes required after recovery

## Hard Rules
- Do not deploy with `kubectl apply` for ArgoCD-managed resources.
- When suggesting live patches (e.g., clear operation state), include the follow-up git change required to make state convergent.
