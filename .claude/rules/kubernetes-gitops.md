---
paths:
  - "kubernetes/**"
  - "Makefile"
  - ".sops.yaml"
---

# Kubernetes GitOps (ArgoCD)

## Pattern
- Kustomize base/overlays: `kubernetes/base/` holds shared defaults, `kubernetes/overlays/<env>/` holds per-cluster overrides
- Multi-cluster: add new overlays (e.g., `overlays/kubevirt-dev/`) — each overlay is a complete cluster declaration
- Application CRs co-located with each component in `overlays/homelab/infrastructure/<component>/application.yaml`
- Multi-source Helm: Application CRs use `sources[]` with `$values` ref for Helm values from this repo

## Bootstrap
- `make argocd-bootstrap` — installs ArgoCD + AppProjects + Applications
- `make argocd-install` — ArgoCD only; `make argocd-password` — retrieve admin password
- AppProjects: `infrastructure` and `apps` (RBAC separation) in `kubernetes/bootstrap/projects/`

## Infrastructure Components (7)
piraeus-operator, metrics-server, cert-approver, nvidia-device-plugin, node-feature-discovery, metallb, gateway-api

## MetalLB
- LoadBalancer for bare-metal; IP `192.168.2.70` (L2 mode), namespace `metallb-system`
- Uses `ServerSideApply=true` + `SkipDryRunOnMissingResource=true` for CRD handling

## Validation
- Per-component: `kubectl kustomize kubernetes/overlays/homelab/infrastructure/<component>/`
- Full overlay build fails (empty base `kustomization.yaml` files) — this is expected
- SOPS covers both `talos/` and `kubernetes/` paths (`.sops.yaml`)
