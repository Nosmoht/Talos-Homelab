# Security Code Review

Date: 2026-03-01  
Reviewer: Staff Engineer / Principal Architect (Kubernetes, CI/CD, Security)  
Scope: `kubernetes/`, `talos/`, root `Makefile`, repository automation posture

## Executive Summary

This repository has strong GitOps fundamentals (ArgoCD app-of-apps, SOPS/KSOPS integration, Talos immutable host OS, and generally clean manifest layout). The primary risks are concentrated in GitOps blast radius and supply-chain mutability:

1. Argo projects are effectively unrestricted (`*` resource and namespace permissions).
2. Argo tracks mutable revisions (`HEAD` and wildcard chart versions), which weakens change control and rollback determinism.
3. Argo repo-server is configured to execute arbitrary kustomize plugins (`--enable-exec`), increasing RCE blast radius if repo trust is violated.
4. Talos control-plane etcd metrics are exposed on `0.0.0.0` over HTTP.
5. Local decrypted Talos secrets are written as plaintext intermediates; ignored by git but still high-impact on workstation compromise.
6. There is no CI security gate (policy-as-code, manifest validation, secret scanning, image/signature verification).

Overall risk rating: **High** (mainly due to control-plane and GitOps control-path exposure, not workload hardening quality).

## Methodology

- Static review of Kubernetes/Talos manifests and make targets.
- Focus areas:
  - GitOps supply chain and change immutability
  - RBAC and namespace/resource blast radius
  - Secret lifecycle and plaintext exposure
  - Control-plane and ingress security defaults
  - CI/CD security controls and policy enforcement
- No runtime cluster access was used; this is source-based analysis.

## Positive Controls Observed

- `SOPS` is configured centrally for Talos and Kubernetes secret files: [.sops.yaml](/Users/thomaskrahn/workspace/homelab-migration/.sops.yaml:1).
- ArgoCD repo-server mounts SOPS AGE key read-only: [kubernetes/base/infrastructure/argocd/values.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/base/infrastructure/argocd/values.yaml:26).
- Dex pod/container hardening is strong (`runAsNonRoot`, read-only root fs, dropped caps): [kubernetes/base/infrastructure/dex/values.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/base/infrastructure/dex/values.yaml:15).
- HTTP to HTTPS redirect is present on gateway: [kubernetes/overlays/homelab/infrastructure/gateway-api/httproute-redirect.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/overlays/homelab/infrastructure/gateway-api/httproute-redirect.yaml:1).
- Dex and Argo are pinned to HTTPS listeners via Gateway `sectionName`: [kubernetes/overlays/homelab/infrastructure/dex/resources/httproute.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/overlays/homelab/infrastructure/dex/resources/httproute.yaml:12), [kubernetes/overlays/homelab/infrastructure/argocd/resources/httproute.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/overlays/homelab/infrastructure/argocd/resources/httproute.yaml:12).

## Findings

## Critical

### 1) Argo AppProject blast radius is effectively cluster-admin

Evidence:
- Infrastructure project allows all destinations/namespaces and all resource kinds: [kubernetes/overlays/homelab/projects/infrastructure.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/overlays/homelab/projects/infrastructure.yaml:19), [kubernetes/overlays/homelab/projects/infrastructure.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/overlays/homelab/projects/infrastructure.yaml:21).
- Apps project has same wildcard model: [kubernetes/overlays/homelab/projects/apps.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/overlays/homelab/projects/apps.yaml:11), [kubernetes/overlays/homelab/projects/apps.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/overlays/homelab/projects/apps.yaml:13).

Impact:
- Any app mapped to these projects can create or mutate any namespace-scoped and cluster-scoped resource.
- A compromised repo PR, chart, or Argo account can fully compromise the cluster.

Recommendation:
- Restrict `destinations` to explicit namespaces per project.
- Use explicit allowlists for `clusterResourceWhitelist` and `namespaceResourceWhitelist`.
- Separate infra vs app projects with non-overlapping RBAC policies.

## High

### 2) GitOps source revisions are mutable (`HEAD` + wildcard chart ranges)

Evidence:
- Root app tracks `HEAD`: [kubernetes/bootstrap/argocd/root-application.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/bootstrap/argocd/root-application.yaml:10).
- Multiple infra applications track repo `HEAD`: [kubernetes/overlays/homelab/infrastructure/argocd/application.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/overlays/homelab/infrastructure/argocd/application.yaml:16), [kubernetes/overlays/homelab/infrastructure/dex/application.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/overlays/homelab/infrastructure/dex/application.yaml:17), [kubernetes/overlays/homelab/infrastructure/cert-manager/application.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/overlays/homelab/infrastructure/cert-manager/application.yaml:16), [kubernetes/overlays/homelab/infrastructure/metrics-server/application.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/overlays/homelab/infrastructure/metrics-server/application.yaml:16).
- Helm charts use floating minor wildcards (for example `9.4.*`, `v1.19.*`, `0.24.*`): [kubernetes/overlays/homelab/infrastructure/argocd/application.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/overlays/homelab/infrastructure/argocd/application.yaml:11).

Impact:
- Non-deterministic deploys and drift over time without explicit change approval.
- Harder incident response and reproducible rollback.

Recommendation:
- Pin Git sources to immutable commit SHAs or signed tags.
- Pin chart versions to exact versions.
- Enforce branch protections and signed commits/tags for release refs.

### 3) ArgoCD repo-server enables executable kustomize plugins

Evidence:
- `kustomize.buildOptions: "--enable-alpha-plugins --enable-exec"`: [kubernetes/base/infrastructure/argocd/values.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/base/infrastructure/argocd/values.yaml:59).

Impact:
- Repo content can execute binaries in repo-server context.
- Expands attack surface from manifest rendering to command execution.

Recommendation:
- Remove `--enable-exec` unless strictly required.
- If required, isolate repo-server (dedicated node pool, restrictive PSP/PSA equivalent controls, egress restrictions, read-only FS, minimal service account perms).
- Prefer purpose-built Argo plugins with explicit allowlisting over general exec.

### 4) etcd metrics exposed over HTTP on all interfaces

Evidence:
- `listen-metrics-urls: http://0.0.0.0:2381`: [talos/patches/controlplane.yaml](/Users/thomaskrahn/workspace/homelab-migration/talos/patches/controlplane.yaml:10).

Impact:
- Control-plane telemetry endpoint is network-reachable plaintext by default.
- Increases reconnaissance and internal lateral movement risk.

Recommendation:
- Bind metrics to loopback or a dedicated management interface.
- If remote scraping is required, enforce network policy / node firewall segmentation and TLS-protected scraping path.

## Medium

### 5) Plaintext decrypted Talos secrets are generated to disk

Evidence:
- Make target decrypts into plaintext `.secrets.dec.yaml`: [talos/Makefile](/Users/thomaskrahn/workspace/homelab-migration/talos/Makefile:50).
- File is gitignored but still present locally: [.gitignore](/Users/thomaskrahn/workspace/homelab-migration/.gitignore:3), [talos/.secrets.dec.yaml](/Users/thomaskrahn/workspace/homelab-migration/talos/.secrets.dec.yaml:1).

Impact:
- Local workstation compromise or accidental backup/sync leakage exposes cluster bootstrap secrets.

Recommendation:
- Use ephemeral temp files with restrictive permissions (`umask 077`, `mktemp`) and trap-based deletion.
- Prefer process substitution or stdin piping where supported by tools.
- Add a pre-commit/CI check to fail on `*.dec.yaml` presence.

### 6) Argo API/UI served in insecure mode behind gateway TLS termination

Evidence:
- `server.insecure: true`: [kubernetes/base/infrastructure/argocd/values.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/base/infrastructure/argocd/values.yaml:46).

Impact:
- In-cluster traffic to Argo server is HTTP; acceptable only with strong east-west trust boundaries.

Recommendation:
- If feasible, enable TLS end-to-end (gateway passthrough/re-encrypt).
- If staying with terminated TLS, enforce namespace network policies and limit in-cluster access to Argo server service.

### 7) Gateway accepts routes from all namespaces

Evidence:
- `allowedRoutes.namespaces.from: All` on HTTP and HTTPS listeners: [kubernetes/overlays/homelab/infrastructure/gateway-api/gateway.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/overlays/homelab/infrastructure/gateway-api/gateway.yaml:12), [kubernetes/overlays/homelab/infrastructure/gateway-api/gateway.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/overlays/homelab/infrastructure/gateway-api/gateway.yaml:23).

Impact:
- Any namespace can attach routes to the shared gateway unless additional Route/Gateway policies constrain it.

Recommendation:
- Restrict to selected namespaces or labels (`from: Selector`).
- Define route admission guardrails per tenant/app namespace.

### 8) OIDC connector does not restrict identity domain

Evidence:
- Google connector configured without `allowedDomains`: [kubernetes/overlays/homelab/infrastructure/dex/values.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/overlays/homelab/infrastructure/dex/values.yaml:4).

Impact:
- Access control relies entirely on downstream RBAC mapping, increasing misconfiguration risk.

Recommendation:
- Add `allowedDomains` (or equivalent claim-based constraints) in Dex connector config.
- Keep least-privilege Argo RBAC defaults (current explicit admin mapping is good but should not be sole boundary).

### 9) Certificate scope limited to wildcard subdomain only

Evidence:
- Cert contains only `*.homelab.ntbc.io`: [kubernetes/overlays/homelab/infrastructure/gateway-api/certificate.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/overlays/homelab/infrastructure/gateway-api/certificate.yaml:11).

Impact:
- Apex `homelab.ntbc.io` is not covered if needed later, causing future TLS surprises.

Recommendation:
- Add explicit apex SAN if intended (`homelab.ntbc.io`).
- Optionally define key algorithm and renewal windows explicitly.

## Low

### 10) Secret manifests encrypt metadata/kind fields in addition to data

Evidence:
- Entire object metadata and kind are encrypted: [kubernetes/overlays/homelab/infrastructure/dex/resources/secret.sops.yaml](/Users/thomaskrahn/workspace/homelab-migration/kubernetes/overlays/homelab/infrastructure/dex/resources/secret.sops.yaml:1).

Impact:
- Operational debugging and linting become harder; low direct security benefit.

Recommendation:
- Encrypt only sensitive keys (`stringData` / `data`) unless there is a specific metadata confidentiality requirement.

### 11) No explicit CI security pipeline found in repository

Evidence:
- No `.github/workflows` or equivalent CI pipeline definitions detected in source.

Impact:
- Policy regressions, secret leaks, and misconfigurations are only detected post-merge/apply.

Recommendation:
- Add CI checks for:
  - `kustomize build` and schema validation (`kubeconform`)
  - policy-as-code (`conftest`/OPA or Kyverno CLI)
  - secrets scanning (`gitleaks`)
  - IaC security (`checkov`/`kubescape`)
  - container/image provenance and signing checks where applicable

## Risk Register (Prioritized)

1. Restrict Argo AppProject permissions and namespace scope.  
2. Replace `HEAD` and wildcard revisions with immutable references.  
3. Remove or tightly contain Argo `--enable-exec`.  
4. Close or segment etcd metrics endpoint exposure.  
5. Eliminate persistent plaintext decrypted secret intermediates.  
6. Add CI security guardrails (validation, policy, secret scanning).

## 30/60/90 Day Remediation Plan

### 0-30 days

- Lock down AppProjects to explicit destinations and resource allowlists.
- Pin root app and infra app Git refs to SHAs/tags.
- Pin Helm charts to exact versions.
- Remove `--enable-exec` or document and isolate its necessity.

### 31-60 days

- Refactor Talos secret generation to ephemeral secure temp handling.
- Restrict Gateway route attachment from `All` to selected namespaces.
- Rework etcd metrics binding and scraping model.

### 61-90 days

- Stand up CI security pipeline with policy gates.
- Add admission policy framework (Kyverno/Gatekeeper) for baseline controls.
- Add periodic dependency and chart update process with signed release promotion.

## Suggested CI/CD Security Baseline

Minimum checks on every pull request:

1. Render and validate all overlays (`kustomize build` + schema validation).  
2. Run policy checks (forbidden wildcards, required securityContext, no mutable tags/refs).  
3. Secret scanning and SOPS policy checks.  
4. Block merges unless all checks pass and at least one code owner approves infra/security-sensitive paths.

## Residual Risk / Assumptions

- This assessment is repository-only and assumes no out-of-band runtime controls (firewalls, cluster policies, service mesh authz) beyond manifests.
- If runtime controls exist, some findings may be partially mitigated but should still be codified in GitOps source-of-truth where possible.
