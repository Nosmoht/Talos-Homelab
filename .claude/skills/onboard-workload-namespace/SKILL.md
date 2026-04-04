---
name: onboard-workload-namespace
description: "Onboard a new namespace: set PNI labels, create ArgoCD Application CR, validate Kyverno admission, and optionally wire Vault ExternalSecrets. Full git-only workflow."
argument-hint: "<namespace> [--profile restricted|managed] [--capabilities cap1,cap2] [--vault]"
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, Write, Edit
---

# Onboard Workload Namespace

## Environment Setup

Read `.claude/environment.yaml` for kubeconfig path and overlay name.
If the file is missing, stop: "Copy `.claude/environment.example.yaml` to `.claude/environment.yaml` and fill in your cluster details."

## Reference Files

Read before acting:
- `docs/platform-network-interface.md` — PNI contract v1, capability catalog, namespace label requirements
- `.claude/rules/kubernetes-gitops.md` — Application CR pattern, directory structure, sync-waves, ArgoCD patterns
- `.claude/rules/manifest-quality.md` — required labels, validation commands
- `kubernetes/overlays/homelab/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml` — registered capabilities (for validation)

Also read 2-3 existing namespace+application pairs as patterns:
```bash
ls kubernetes/overlays/homelab/infrastructure/*/resources/namespace.yaml
```

If `--vault`, also read:
- `docs/external-secrets-customer-guide.md` — Steps 1-3 (SecretStore + ExternalSecret pattern)

## Inputs

- `<namespace>`: Name of the new namespace (kebab-case)
- `--profile restricted|managed`: Network profile. Default: `restricted`. Use `managed` only for platform operators.
- `--capabilities cap1,cap2`: Comma-separated capability opt-ins from the registry.
- `--vault`: Wire Vault ExternalSecrets (follows `docs/external-secrets-customer-guide.md`).

## Scope Guard

If the user wants to ADD a new PNI capability (not consume an existing one):
- Stop and suggest: "To add a new capability, use `/pni-capability-add` first."

If a requested capability does NOT exist in `capability-registry-configmap.yaml`:
- Stop and report: "Capability '<name>' is not registered. Run `/pni-capability-add` first, then re-run this skill."

If the namespace already exists in the overlay:
- Stop and report: "Namespace <name> already has an overlay at `kubernetes/overlays/homelab/infrastructure/<component>/`. Review the existing files instead of creating new ones."

## Workflow

### 1. Gather and validate inputs

Resolve:
- Component directory name (usually matches namespace, confirm with user if different)
- Workload type: app, operator, or tenant
- Network profile: `restricted` (default) or `managed`
- Capabilities: validate each against `capability-registry-configmap.yaml`

If any capability is not in the registry, stop (see scope guard above).

### 2. Author Namespace manifest

Create:
```
kubernetes/overlays/homelab/infrastructure/<component>/resources/namespace.yaml
```

Required labels:
```yaml
labels:
  platform.io/network-interface-version: "v1"
  platform.io/network-profile: <restricted|managed>
  # For each capability:
  platform.io/consume.<capability>: "true"
  # Kubernetes recommended labels:
  app.kubernetes.io/name: <namespace>
  app.kubernetes.io/managed-by: argocd
```

Never set provider-reserved labels (`platform.io/provider`, `platform.io/managed-by`, `platform.io/capability`).

### 3. Author ArgoCD Application CR

Follow the multi-source Helm pattern from `.claude/rules/kubernetes-gitops.md`.

Place at:
```
kubernetes/overlays/homelab/infrastructure/<component>/application.yaml
```

Required annotations:
- `argocd.argoproj.io/sync-wave: "0"` (infrastructure wave)

Reference `kubernetes/base/infrastructure/<component>/` for base Helm values.

### 4. Verify AppProject permissions

Read `kubernetes/overlays/homelab/projects/infrastructure.yaml`.

Confirm:
- Target namespace is in the `destinations` list
- Chart repository is in `sourceRepos`

If not, add the missing entries and note this in the commit message.

### 5. Create Helm values files (if Helm chart)

Create portable defaults:
```
kubernetes/base/infrastructure/<component>/values.yaml
```

Create cluster-specific overrides:
```
kubernetes/overlays/homelab/infrastructure/<component>/values.yaml
```

### 6. Wire Vault ExternalSecrets (only if --vault)

Follow `docs/external-secrets-customer-guide.md` Steps 1-3:
1. Create `SecretStore` in the namespace referencing the Vault cluster secret store
2. Create `ExternalSecret`(s) referencing Vault paths
3. If any static secrets are needed, create them as `*.sops.yaml` — the pre-write hook will verify SOPS encryption

### 7. Create kustomization.yaml

Create:
```
kubernetes/overlays/homelab/infrastructure/<component>/kustomization.yaml
```

Include all created resources. Follow existing overlay kustomization patterns.

## User Confirmation Gate

Present all files to be created for user review before writing:
- `resources/namespace.yaml`
- `application.yaml`
- `kustomization.yaml`
- `values.yaml` (base and overlay)
- ExternalSecret files (if --vault)
- AppProject changes (if needed)

Wait for explicit confirmation before writing.

### 8. Validate

Run:
```bash
make validate-kyverno-policies
kubectl kustomize kubernetes/overlays/homelab > /dev/null
KUBECONFIG=<kubeconfig> kubectl apply -k kubernetes/overlays/homelab --dry-run=client
```

If any fails, stop and report the specific error. Do not commit until all pass.

### 9. Commit and push

```bash
git add kubernetes/overlays/homelab/infrastructure/<component>/
git add kubernetes/base/infrastructure/<component>/
git add kubernetes/overlays/homelab/projects/infrastructure.yaml  # if modified
git commit -m "feat(<component>): onboard <namespace> namespace"
git push
```

### 10. Post-push verification (after ArgoCD sync)

Run:
```bash
KUBECONFIG=<kubeconfig> kubectl get ns <namespace> --show-labels
KUBECONFIG=<kubeconfig> kubectl get application -n argocd <component>
KUBECONFIG=<kubeconfig> kubectl get policyreport -n <namespace>
```

Confirm:
- Namespace exists with correct PNI labels
- ArgoCD Application is Healthy+Synced
- No Kyverno policy violations in the PolicyReport

## Hard Rules

- NEVER set provider-reserved labels on consumer namespaces
- NEVER `kubectl apply` ArgoCD-managed resources — git commit + push only
- Do NOT opt `privileged` namespaces into `gateway-backend` (activates default-deny without matching policies)
- Capabilities MUST exist in the registry before consumer opt-in
- All files MUST pass Kyverno admission validation before committing
