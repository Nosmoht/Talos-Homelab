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
- Gateway API CRDs (v1.2.1 experimental channel) installed via `extraManifests` — must appear **before** Cilium URL (CRDs must exist before Cilium watches them)
- Enabled via `enable-gateway-api: "true"` in Cilium ConfigMap + RBAC in cilium-operator ClusterRole
- Cilium auto-creates `cilium` GatewayClass
- For each Gateway: creates `cilium-gateway-<name>` Deployment (Envoy) + LoadBalancer Service
- Gateway resource in `kubernetes/overlays/<overlay>/infrastructure/gateway-api/` (ArgoCD-managed, overlay name from `.claude/environment.yaml`)

## Routing Pattern
- GatewayClass → Gateway → HTTPRoute
- **HARD CONSTRAINT: Gateway API only, NO Ingress** — no Ingress resources or Ingress controllers

## ArgoCD Sync — Gateway API Gotchas
- Gateway API webhook auto-defaults fields (e.g., `group: ""` on certificateRefs, `matches: [{path: {type: PathPrefix, value: /}}]` on HTTPRoutes) — always include these explicitly in manifests to prevent perpetual OutOfSync drift
- HTTP listener uses `from: Same` (redirect HTTPRoute is same namespace as Gateway); HTTPS listener uses `from: Selector` with `edge-public: "true"` label
