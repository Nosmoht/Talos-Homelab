# Kubernetes Manifests Review

**Date:** 2026-03-01
**Scope:** All 74 manifests in `kubernetes/` directory
**Reviewer:** Staff Engineer / Principal Architect review

## Architecture Summary

The architecture is solid — clean app-of-apps pattern, consistent multi-source Application CRs, proper base/overlay separation, and well-structured SOPS/KSOPS integration.

### Positive Patterns

- **Consistent multi-source Application CRs** — Helm chart + `$values` ref + kustomize resources path is clean and well-applied
- **SOPS/KSOPS integration** — exec-based plugin with AGE backend properly wired through ArgoCD repo-server
- **Sync-wave ordering** — projects(-1) → infrastructure(0) → apps(1) is correct
- **Dex security context** — `runAsNonRoot`, `readOnlyRootFilesystem`, `capabilities.drop: ALL` is exemplary
- **Piraeus TLS** — full cert-manager-managed PKI chain for LINSTOR API and internal comms
- **StorageClass** — `xfs` with DRBD replication, auto-place, and default class annotation
- **`SkipDryRunOnMissingResource`** on MetalLB and piraeus-operator correctly handles CRD ordering

---

## Findings

### Critical

| # | Component | Finding |
|---|-----------|---------|
| 1 | **dex** | `base/dex/values.yaml` — `storage.type: kubernetes` is deprecated and removed in Dex chart ≥0.19. With `targetRevision: 0.24.*`, this will break or is already broken. Change to `storage.type: memory`. |

### High

| # | Component | Finding |
|---|-----------|---------|
| 2 | **dex** | HTTPRoute missing `sectionName: https` — Dex (OIDC provider) is reachable over plain HTTP, meaning OAuth tokens can transit unencrypted. |
| 3 | **piraeus** | `storage-pool-autovg.yaml` — `NODE_FILTER_REGEX: ^node-[0-9]+$` excludes `node-gpu-01`. If that node should participate in LINSTOR storage, the regex must be `^node-`. If intentionally excluded, document why. |
| 4 | **bootstrap** | Chart version skew — bootstrap pins `argo-cd` chart to `7.8.*` but the self-managed Application uses `9.4.*`. This is a major version jump on first self-management sync. Either align them or document the intentional launcher pattern. |
| 5 | **projects** | Both `infrastructure` and `apps` AppProjects have all-wildcard `sourceRepos`, `destinations`, and resource whitelists. This provides zero project isolation. Lock `sourceRepos` to actual repos/chart URLs and `destinations.server` to `https://kubernetes.default.svc`. |

### Medium

| # | Component | Finding |
|---|-----------|---------|
| 6 | **argocd** | HTTPRoute also missing `sectionName: https` — ArgoCD reachable over plain HTTP. |
| 7 | **argocd** | `global.domain: ""` in base values — should be `argocd.homelab.ntbc.io` to avoid chart behaviors that depend on this field. |
| 8 | **argocd** | sops-age volumeMount missing `readOnly: true`. |
| 9 | **all apps** | No `retry` block on any Application CR. Transient CRD-ordering failures during bootstrap require manual re-sync. Add `retry: {limit: 5, backoff: {duration: 5s, factor: 2, maxDuration: 3m}}`. |
| 10 | **cert-manager** | Missing `SkipDryRunOnMissingResource=true` — ClusterIssuers will fail dry-run on fresh cluster before CRDs exist. MetalLB and piraeus-operator have this; cert-manager should too. |
| 11 | **cert-manager** | SOPS secret has `kind`, `metadata.name`, and `metadata.namespace` all encrypted. Unconventional — makes debugging impossible without the AGE key. Consider encrypting only `data` fields. |
| 12 | **gateway-api** | No dedicated ArgoCD Application — resources are bundled into the root app with implicit ordering dependencies on cert-manager and MetalLB. Consider adding sync-wave annotations (e.g., wave 5) to the gateway-api resources. |
| 13 | **gateway-api** | Gateway in `default` namespace — non-standard; limits future isolation. HTTP listener has no HTTP→HTTPS redirect. |
| 14 | **gateway-api** | `gateway-endpointslice.yaml` — static node IPs require manual updates on any node change. Known tradeoff per the comments, but fragile. |
| 15 | **piraeus** | `targetRevision: 2.*` floats across minors for a stateful storage operator. Pin to `2.5.*` or tighter. |
| 16 | **piraeus** | `LinstorSatelliteConfiguration` has no `nodeSelector` — assumes all nodes have `/dev/nvme0n1`. |
| 17 | **piraeus** | `drbd-reactor` ServiceMonitor is in `piraeus-datastore` but `linstor-csi-nfs` ServiceMonitor is in `monitoring` — inconsistent namespace placement. |
| 18 | **piraeus** | `storage-pool-autovg.yaml` — reconciler uses `pods/exec` RBAC (elevated), runs as root with no `securityContext`, and uses `alpine/kubectl` from Docker Hub (unofficial, rate-limit risk). |
| 19 | **nvidia** | DaemonSet runs on all 7 nodes — should be restricted to GPU nodes via NFD label `feature.node.kubernetes.io/pci-10de.present: "true"`. |
| 20 | **dex** | No `allowedDomains` on the Google OIDC connector. Combined with `policy.default: role:admin`, any Google account can get ArgoCD admin access. |
| 21 | **metrics-server** | `--kubelet-insecure-tls` still present alongside `kubelet-serving-cert-approver`. Either remove the flag (cert-approver handles it) or document the intentional fallback. |

### Low

| # | Component | Finding |
|---|-----------|---------|
| 22 | **root app** | Missing `resources-finalizer.argocd.argoproj.io` — deleting root app orphans all children. |
| 23 | **argocd base** | `kustomization.yaml` is empty and unreferenced — dead file, delete it. |
| 24 | **dex** | Missing `ServerSideApply=true` — inconsistent with argocd, cert-manager, metallb, piraeus-operator. |
| 25 | **cert-manager** | No resource requests/limits, no `securityContext` hardening in base values. |
| 26 | **cert-manager** | No `ignoreDifferences` for CRD `caBundle` injection — may cause perpetual OutOfSync. |
| 27 | **certificate** | No `privateKey.algorithm` set (defaults RSA 2048). No explicit `duration`/`renewBefore`. Wildcard cert doesn't include apex `homelab.ntbc.io`. |
| 28 | **namespaces** | No PSA labels (`pod-security.kubernetes.io/enforce`) on any namespace. |
| 29 | **piraeus** | Talos-specific LVM path redirections (`/var/etc/lvm/`) lack explanatory comments. |
| 30 | **piraeus** | `tls.yaml` CA certs use RSA 2048 default — ECDSA P-256 would be more efficient. |
