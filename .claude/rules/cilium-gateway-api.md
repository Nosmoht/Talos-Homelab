---
paths:
  - "kubernetes/bootstrap/cilium/**"
  - "kubernetes/**/gateway-api/**"
  - "talos/patches/controlplane.yaml"
---

# Cilium CNI & Gateway API

## Cilium Manifest
- Location: `kubernetes/bootstrap/cilium/cilium.yaml` (~1686 lines)
- Referenced via `extraManifests` URL in `talos/patches/controlplane.yaml`
- Cilium stays under `bootstrap/` — CNI must exist before ArgoCD can run
- **Repo must be public** (or accessible from nodes) for extraManifests URL to work

## Gateway API
- Cilium is the Gateway API implementation (Envoy proxies)
- Gateway API CRDs (v1.2.1) installed via `extraManifests` — must appear **before** Cilium URL (CRDs must exist before Cilium watches them)
- Enabled via `enable-gateway-api: "true"` in Cilium ConfigMap + RBAC in cilium-operator ClusterRole
- Cilium auto-creates `cilium` GatewayClass
- For each Gateway: creates `cilium-gateway-<name>` Deployment (Envoy) + LoadBalancer Service
- `homelab-gateway` Gateway resource in `kubernetes/overlays/homelab/infrastructure/gateway-api/` (ArgoCD-managed)

## Routing Pattern
- GatewayClass → Gateway → HTTPRoute
- **HARD CONSTRAINT: Gateway API only, NO Ingress** — no Ingress resources or Ingress controllers
