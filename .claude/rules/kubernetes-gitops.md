---
paths:
  - "kubernetes/**"
  - "Makefile"
  - ".sops.yaml"
---

# Kubernetes GitOps (ArgoCD)

## App-of-Apps Pattern
- **Root Application** (`root`) in `default` project points to `kubernetes/overlays/homelab/`
- Root app manages: AppProjects, all child Application CRs, namespaces, gateway-api resources
- **ArgoCD self-management**: `argocd` Application CR manages its own Helm chart + HTTPRoute
- Bootstrap is minimal: `make argocd-install` (Helm) + `make argocd-bootstrap` (applies root app only)
- After bootstrap, all changes go through git — ArgoCD auto-syncs

## Sync-Wave Ordering
- **Wave -1**: AppProjects (via `commonAnnotations` in `projects/kustomization.yaml`)
- **Wave 0**: Infrastructure Application CRs + namespaces + gateway-api resources (default)
- **Wave 1**: App Application CRs (via `commonAnnotations` in `apps/kustomization.yaml`)

## Directory Structure
```
kubernetes/
├── base/infrastructure/<component>/
│   ├── kustomization.yaml          # optional (only if has namespace.yaml)
│   └── values.yaml                 # shared Helm values
├── overlays/homelab/
│   ├── kustomization.yaml          # resources: [projects, infrastructure, apps]
│   ├── projects/
│   │   ├── kustomization.yaml      # commonAnnotations sync-wave: "-1"
│   │   ├── infrastructure.yaml     # AppProject
│   │   └── apps.yaml               # AppProject
│   ├── infrastructure/
│   │   ├── kustomization.yaml      # lists all infra components
│   │   └── <component>/
│   │       ├── kustomization.yaml  # references base (if needed) + application.yaml
│   │       ├── application.yaml    # ArgoCD Application CR
│   │       ├── values.yaml         # overlay-specific Helm values (optional)
│   │       └── resources/          # extra manifests synced by the Application (optional)
│   └── apps/
│       └── kustomization.yaml      # commonAnnotations sync-wave: "1", resources: []
└── bootstrap/argocd/
    ├── namespace.yaml              # argocd namespace (used by Makefile)
    ├── root-application.yaml       # the one root Application CR (applied by Makefile)
    └── kustomization.yaml          # legacy, unused
```

## Application CR Pattern (multi-source Helm)
All infrastructure Application CRs follow this pattern:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: <component>
  namespace: argocd
spec:
  project: infrastructure
  sources:
    - repoURL: <helm-chart-repo-url>
      chart: <chart-name>
      targetRevision: '<version-glob>'
      helm:
        valueFiles:
          - $values/kubernetes/base/infrastructure/<component>/values.yaml
          - $values/kubernetes/overlays/homelab/infrastructure/<component>/values.yaml  # optional overlay
    - repoURL: https://github.com/Nosmoht/Talos-Homelab.git
      targetRevision: HEAD
      ref: values
    - repoURL: https://github.com/Nosmoht/Talos-Homelab.git    # optional: extra resources
      targetRevision: HEAD
      path: kubernetes/overlays/homelab/infrastructure/<component>/resources
  destination:
    server: https://kubernetes.default.svc
    namespace: <target-namespace>
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true          # used by: argocd, cert-manager, metallb, piraeus-operator
      - SkipDryRunOnMissingResource=true  # used by: metallb, piraeus-operator (CRD ordering)
```

## Infrastructure Components (10)
| Component | Chart Repo | Namespace | Has resources/ | Has overlay values |
|-----------|-----------|-----------|----------------|-------------------|
| argocd | argoproj.github.io/argo-helm | argocd | yes (httproute) | no |
| cert-manager | charts.jetstack.io | cert-manager | yes (issuers, secrets) | no |
| cert-approver | postfinance.github.io/kubelet-serving-cert-approver | kube-system | no | no |
| dex | charts.dexidp.io | dex | yes (httproute, secrets) | yes |
| metallb | metallb.universe.tf | metallb-system | yes (ippool, l2adv) | no |
| metrics-server | kubernetes-sigs.github.io/metrics-server | kube-system | no | no |
| node-feature-discovery | kubernetes-sigs.github.io/.../charts | node-feature-discovery | no | no |
| nvidia-device-plugin | nvidia.github.io/k8s-device-plugin | kube-system | no | no |
| piraeus-operator | charts.piraeus.io | piraeus-datastore | yes (linstor config) | no |
| gateway-api | N/A (raw resources, no Application) | default | N/A | N/A |

Components with base namespace.yaml (referenced by overlay kustomization): cert-manager, dex, piraeus-operator

## SOPS/KSOPS
- Encrypted secrets: `secret.sops.yaml` + `ksops-generator.yaml` in component resources/
- Components using SOPS: cert-manager, dex
- ArgoCD repo-server has ksops binary + SOPS_AGE_KEY_FILE mounted

## Makefile Targets
- `make argocd-install` — namespace + Helm install + sops-age-key secret + wait
- `make argocd-bootstrap` — argocd-install + apply root-application.yaml
- `make argocd-password` — retrieve initial admin password
- `make argocd-oidc` — patch argocd-secret with OIDC client secret from encrypted dex secret

## Validation
- Full overlay: `kubectl apply -k kubernetes/overlays/homelab/ --dry-run=client`
- Per-component: `kubectl kustomize kubernetes/overlays/homelab/infrastructure/<component>/`
