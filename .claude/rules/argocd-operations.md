---
paths:
  - "kubernetes/**"
  - "docs/day2-operations.md"
  - "Makefile"
---

# ArgoCD Day-2 Operations

## Operator Intent
- Treat git as source of truth for ArgoCD-managed resources.
- Use `kubernetes/bootstrap/**` only for bootstrap and emergency recovery.

## Safe Change Sequence
1. Render locally before editing (`kubectl kustomize kubernetes/overlays/<overlay>` — overlay name from `.claude/environment.yaml`).
2. Apply manifest changes in git only.
3. Verify ArgoCD application health/sync status after push.
4. Capture verification evidence in PR notes.

## Drift and Retry Handling
- If sync is stuck on stale `operationState`, clear operation state and force refresh.
- If retries are exhausted at a stale revision, restart `argocd-application-controller` to re-resolve branch head.
- For immutable selector chart upgrades, delete conflicting resources first, then resync.

## Hard Rules
- Never use `kubectl apply` for resources already managed by ArgoCD.
- Never mask drift with `ignoreDifferences` until webhook/defaulting behavior is verified.
- Always include explicit fields known to be defaulted by Gateway API webhooks to avoid perpetual OutOfSync.
