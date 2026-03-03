---
paths:
  - "kubernetes/**/*.yaml"
  - "kubernetes/**/*.yml"
---

# Kubernetes Manifest Quality Gate

## Required Conventions
- Use Kubernetes recommended labels (`app.kubernetes.io/*`) on all non-generated resources.
- Keep namespaces explicit where required by object kind.
- Prefer one logical resource group per file directory (`application.yaml`, `kustomization.yaml`, `values.yaml`, `resources/`).

## Review Checklist
- Kustomize references are relative and resolvable.
- Helm values only override what differs from base values.
- Gateway API resources specify fields that webhooks default (match/group/path typing).
- CiliumNetworkPolicies include explicit endpoint selectors and ports that match post-DNAT behavior.
- SOPS secrets stay encrypted (`*.sops.yaml`) and ksops generators are referenced in local `kustomization.yaml`.

## Validation Commands
- `kubectl kustomize kubernetes/overlays/homelab`
- `kubectl apply -k kubernetes/overlays/homelab --dry-run=client`
