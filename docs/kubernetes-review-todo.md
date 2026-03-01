# Kubernetes Review — Findings Tracker

| # | Severity | Component | Finding | Status |
|---|----------|-----------|---------|--------|
| 1 | Critical | dex | `storage.type: kubernetes` deprecated — change to `memory` | DONE |
| 2 | High | dex | HTTPRoute missing `sectionName: https` — OIDC tokens over plain HTTP | DONE |
| 3 | High | piraeus | `NODE_FILTER_REGEX` excludes `node-gpu-01` — document or fix | DONE |
| 4 | High | bootstrap | Chart version skew `7.8.*` vs `9.4.*` — align or document | DONE |
| 5 | High | projects | All-wildcard `sourceRepos`/`destinations` — no project isolation | DONE |
| 6 | Medium | argocd | HTTPRoute missing `sectionName: https` | DONE |
| 7 | Medium | argocd | `global.domain: ""` — should be `argocd.homelab.ntbc.io` | DONE |
| 8 | Medium | argocd | sops-age volumeMount missing `readOnly: true` | DONE |
| 9 | Medium | all apps | No `retry` block on any Application CR | DONE |
| 10 | Medium | cert-manager | Missing `SkipDryRunOnMissingResource=true` | DONE |
| 11 | Medium | cert-manager | SOPS secret fully encrypted including `kind`/`metadata` | OPEN |
| 12 | Medium | gateway-api | Implicit ordering deps — fixed with sync-wave 5 | DONE |
| 13 | Medium | gateway-api | No HTTP→HTTPS redirect — added redirect HTTPRoute | DONE |
| 14 | Medium | gateway-api | Static node IPs in EndpointSlice — fragile | DONE |
| 15 | Medium | piraeus | `targetRevision: 2.*` too broad — pinned to `2.10.*` | DONE |
| 16 | Medium | piraeus | `LinstorSatelliteConfiguration` and `LinstorCluster` no `nodeSelector` — exclude `node-gpu-01` | DONE |
| 17 | Medium | piraeus | ServiceMonitor namespace inconsistency — standardized to `monitoring` | DONE |
| 18 | Medium | piraeus | autovg reconciler — added securityContext, switched to bitnami/kubectl | DONE |
| 19 | Medium | nvidia | DaemonSet on all nodes — restricted via NVIDIA kernel module label affinity | DONE |
| 20 | Medium | dex/argocd | No access restriction — any Google account gets admin; fixed via ArgoCD RBAC email grant | DONE |
| 21 | Medium | metrics-server | `--kubelet-insecure-tls` removed — cert-approver handles certs | DONE |
| 22 | Low | root app | Missing `resources-finalizer.argocd.argoproj.io` | OPEN |
| 23 | Low | argocd base | Empty `kustomization.yaml` — dead file | OPEN |
| 24 | Low | dex | Missing `ServerSideApply=true` — inconsistent | OPEN |
| 25 | Low | cert-manager | No resource requests/limits or securityContext | OPEN |
| 26 | Low | cert-manager | No `ignoreDifferences` for CRD caBundle | OPEN |
| 27 | Low | certificate | No privateKey algorithm, duration, or apex domain | OPEN |
| 28 | Low | namespaces | No PSA labels on any namespace | OPEN |
| 29 | Low | piraeus | LVM path redirections lack comments | OPEN |
| 30 | Low | piraeus | CA certs use RSA 2048 — ECDSA preferred | OPEN |
