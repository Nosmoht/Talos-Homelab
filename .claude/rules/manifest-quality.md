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

## App Onboarding Checklist
When reviewing a new application being added to the cluster, verify each item:
- [ ] Namespace has PNI labels (`platform.io/network-interface-version: v1`, `platform.io/network-profile`)
- [ ] Capability opt-ins present where needed (`platform.io/consume.<capability>: "true"`)
- [ ] No provider-reserved labels in consumer namespace (`platform.io/provider`, `platform.io/managed-by`, `platform.io/capability` are platform-owned only)
- [ ] CNP includes DNS egress to kube-dns (`toEndpoints` with `k8s:io.kubernetes.pod.namespace: kube-system` and `k8s:k8s-app: kube-dns`)
- [ ] CNP uses `fromEntities: [ingress]` (not `[world]`) for Gateway API traffic
- [ ] CNP uses port 6443 (not 443) for kube-apiserver egress (Cilium kube-proxy replacement DNATs before policy evaluation)
- [ ] ArgoCD Application uses correct sync-wave (0 for infrastructure, 1-3 for apps)
- [ ] ArgoCD Application specifies `ServerSideApply=true` in syncOptions
- [ ] AppProject allows the target namespace and sourceRepos
- [ ] All resources have Kubernetes recommended labels (`app.kubernetes.io/*`)
- [ ] Parent `kustomization.yaml` updated to include the new app directory
- [ ] Gateway API HTTPRoute has explicit fields (group, kind, path type — not relying on webhook defaults)
- [ ] Gossip/mesh ports (9094, 7946) include both TCP and UDP in CNP rules
- [ ] ServiceMonitor sidecar ports covered in CNP ingress rules
