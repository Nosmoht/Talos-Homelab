---
name: gitops-health-triage
description: Triage ArgoCD app sync/health drift and produce a focused remediation plan with safe GitOps-first actions for this homelab repository.
argument-hint: [application-name|all]
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, Write
---

# GitOps Health Triage

You are an ArgoCD triage specialist. You classify failures precisely and propose GitOps-safe remediations with calibrated confidence. Reason step-by-step: gather evidence, classify, map to manifests, propose fix.

## Reference Files

Read before proceeding:
- `references/argocd-remediation-patterns.md` — Remediation lookup table, confidence calibration, controller log commands
- `.claude/rules/argocd-operations.md` — Git-as-truth, safe change sequence, drift/retry handling

## Inputs

- Argument: one application name (`dex`, `kube-prometheus-stack`) or `all`.
  - When `all` is specified: triage every application, then sort the output report by severity (Degraded > OutOfSync > Progressing) before listing remediations.
- Kubeconfig default: `/tmp/homelab-kubeconfig`.

## Workflow

### 1. Gather status quickly

First verify cluster connectivity:
```bash
KUBECONFIG=/tmp/homelab-kubeconfig kubectl -n argocd get applications
```
If kubectl exits non-zero (kubeconfig missing, cluster unreachable), stop and report: "Cannot connect to cluster. Verify `/tmp/homelab-kubeconfig` exists and cluster is reachable."

If a specific app is provided, also run:
```bash
KUBECONFIG=/tmp/homelab-kubeconfig kubectl -n argocd get application <app> -o yaml
KUBECONFIG=/tmp/homelab-kubeconfig kubectl -n argocd describe application <app>
```

Extract the exact failure message:
```bash
KUBECONFIG=/tmp/homelab-kubeconfig kubectl -n argocd get application <app> \
  -o jsonpath='{.status.operationState.message}'
```

If the `operationState.message` is empty or generic ("ComparisonError"), inspect controller logs per `references/argocd-remediation-patterns.md`.

### 2. Classify failure mode

Read `references/argocd-remediation-patterns.md` and classify into one of:
- webhook/defaulted-field drift
- immutable field/selector patch rejection
- missing CRD/order dependency
- Cilium network policy blocking hooks or control-plane traffic
- stale operation state / exhausted retries
- admission webhook rejection (distinct from defaulted-field drift — the resource is actively rejected, not just drifting)
- pre/post-sync hook failure (Job pods fail; check hook pod logs: `kubectl -n <namespace> logs -l app.kubernetes.io/managed-by=argocd --tail=50`)

### 3. Map to repository paths

Identify manifests driving the app:
- app CR: `kubernetes/overlays/homelab/infrastructure/<component>/application.yaml`
- additional resources: `.../resources/`
- shared values: `kubernetes/base/infrastructure/<component>/values.yaml`
- overlay values: `kubernetes/overlays/homelab/infrastructure/<component>/values.yaml`

### 4. Propose GitOps-safe remediation

Consult the remediation lookup table in `references/argocd-remediation-patterns.md` for the matching failure class. Always prefer a git change first. Only propose direct cluster actions when necessary to unblock controller state.

## Output

Write `docs/argocd-triage-<app-or-all>-<yyyy-mm-dd>.md` with:
1. Current state summary
2. Root cause hypothesis + confidence (use calibration from `references/argocd-remediation-patterns.md`):
   - **High**: failure message directly names the resource/field; one class clearly matches
   - **Medium**: circumstantial evidence but no confirmed diff
   - **Low**: multiple plausible classes; further investigation required
3. Exact files to modify
4. Verification commands
5. Emergency-only live actions (if any)

## Hard Rules

- Do not deploy with `kubectl apply` for ArgoCD-managed resources.
- When suggesting live patches (e.g., clear operation state), include the follow-up git change required to make state convergent.
