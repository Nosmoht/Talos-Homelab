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

Extract before running any commands:
```bash
KUBECONFIG=$(yq '.kubeconfig' .claude/environment.yaml)
OVERLAY=$(yq '.cluster.overlay // "homelab"' .claude/environment.yaml)
```

## Reference Files

Read before acting:
- `.claude/environment.yaml` — kubeconfig, overlay name
- `docs/platform-network-interface.md` — PNI contract v1, capability catalog, namespace label requirements
- `.claude/rules/kubernetes-gitops.md` — Application CR pattern, directory structure, sync-waves, ArgoCD patterns
- `.claude/rules/manifest-quality.md` — required labels, validation commands
- `kubernetes/overlays/homelab/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml` — registered capabilities (for validation)
- `kubernetes/overlays/homelab/projects/infrastructure.yaml` — AppProject destinations and sourceRepos

If `--vault`, also read:
- `docs/external-secrets-customer-guide.md` — Steps 1-3 (SecretStore + ExternalSecret pattern)

Also read 2-3 existing namespace+application pairs as patterns:
```bash
ls kubernetes/overlays/homelab/infrastructure/*/resources/namespace.yaml
```

## Inputs

- `<namespace>`: Name of the new namespace (kebab-case)
- `--profile restricted|managed`: Network profile. Default: `restricted`. Use `managed` only for platform operators.
- `--capabilities cap1,cap2`: Comma-separated capability opt-ins from the registry.
- `--vault`: Wire Vault ExternalSecrets (follows `docs/external-secrets-customer-guide.md`).

## Scope Guard

Resolve the component directory name first — it usually matches the namespace name. Confirm with the user if different. Store as `COMPONENT`.

Check if the component already has an overlay:
```bash
ls kubernetes/overlays/homelab/infrastructure/$COMPONENT/ 2>/dev/null
```
If the directory exists, stop: "Namespace $COMPONENT already has an overlay at `kubernetes/overlays/homelab/infrastructure/$COMPONENT/`. Review existing files instead."

If the user wants to ADD a new PNI capability (not consume an existing one):
- Stop. Suggest `/pni-capability-add` first.

For each capability in `--capabilities`, verify it exists in `capability-registry-configmap.yaml`:
```bash
grep "<capability>" kubernetes/overlays/homelab/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml
```
If any capability is not found, stop: "Capability '<name>' is not registered. Run `/pni-capability-add` first, then re-run this skill."

If `--vault` is specified, warn: "The Vault KV paths referenced in ExternalSecrets must exist in Vault before they can sync. Ensure the paths are provisioned before or immediately after this onboarding."

## Workflow — Phase 1: Plan (do not write any files yet)

Gather all information and draft all file contents in memory. Do not use Write or Edit tools during Phase 1.

### 1. Determine inputs

Resolve:
- `COMPONENT` (component directory name, confirmed with user)
- `NAMESPACE` (namespace name, from argument)
- Workload type: app, operator, or tenant
- Network profile: `restricted` (default) or `managed`
- Capabilities: confirmed valid list from registry check above

### 2. Draft Namespace manifest

Draft contents for:
```
kubernetes/overlays/homelab/infrastructure/$COMPONENT/resources/namespace.yaml
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

### 3. Draft ArgoCD Application CR

Draft contents for:
```
kubernetes/overlays/homelab/infrastructure/$COMPONENT/application.yaml
```

Follow the multi-source Helm pattern from `.claude/rules/kubernetes-gitops.md`.
Required annotations: `argocd.argoproj.io/sync-wave: "0"` (infrastructure wave).

### 4. Check AppProject permissions

Read `kubernetes/overlays/homelab/projects/infrastructure.yaml`.

Check whether the target namespace is in the `destinations` list and whether the chart repository is in `sourceRepos`. Note any missing entries — these will be added to the draft, not committed silently.

### 5. Draft Helm values files (if Helm chart)

Draft contents for:
```
kubernetes/base/infrastructure/$COMPONENT/values.yaml       (portable defaults)
kubernetes/overlays/homelab/infrastructure/$COMPONENT/values.yaml  (cluster-specific overrides)
```

### 6. Draft Vault ExternalSecrets (only if --vault)

Follow `docs/external-secrets-customer-guide.md` Steps 1-3. Draft:
- `SecretStore` in the namespace
- `ExternalSecret`(s) referencing the Vault paths the user specified

Note: SOPS-encrypted static secrets must be created as `*.sops.yaml` — the pre-write hook will verify SOPS encryption automatically.

### 7. Draft kustomization.yaml

Draft contents for:
```
kubernetes/overlays/homelab/infrastructure/$COMPONENT/kustomization.yaml
```

Include all resources drafted above.

---

## Phase 2: Confirmation Gate

Present ALL drafted file contents to the user for review before writing anything:
- `resources/namespace.yaml` (full content)
- `application.yaml` (full content)
- `kustomization.yaml` (full content)
- `values.yaml` base and overlay (full content)
- ExternalSecret files if `--vault` (full content)
- AppProject changes if namespace or repo was missing (full diff)

Ask: "Confirm to write all files and proceed? (yes/no)"

**Do not write any files until the user explicitly confirms.**

---

## Workflow — Phase 3: Execute (only after confirmation)

### 8. Write files

Write all confirmed files using the Write and Edit tools. Create the component directory structure:
```bash
mkdir -p kubernetes/overlays/homelab/infrastructure/$COMPONENT/resources
mkdir -p kubernetes/base/infrastructure/$COMPONENT
```

If AppProject entries are missing, use Edit to add them to `kubernetes/overlays/homelab/projects/infrastructure.yaml`. If edit fails, stop and report the specific error.

### 9. Validate

Run:
```bash
make validate-kyverno-policies
kubectl kustomize kubernetes/overlays/$OVERLAY > /dev/null
KUBECONFIG=$KUBECONFIG kubectl apply -k kubernetes/overlays/$OVERLAY --dry-run=client
```

If any fails, stop and report the specific error. Do not commit until all three pass.

### 10. Commit and push

```bash
git add kubernetes/overlays/homelab/infrastructure/$COMPONENT/
git add kubernetes/base/infrastructure/$COMPONENT/
git add kubernetes/overlays/homelab/projects/infrastructure.yaml  # only if modified
git commit -m "feat($COMPONENT): onboard $NAMESPACE namespace"
git push
```

### 11. Post-push verification (after ArgoCD sync)

ArgoCD's default polling interval is up to 3 minutes. After pushing, wait for sync before checking. Run:
```bash
KUBECONFIG=$KUBECONFIG kubectl -n argocd get application $COMPONENT -w --timeout=5m
```
Wait until Application shows `Synced` and `Healthy`. Then verify:
```bash
KUBECONFIG=$KUBECONFIG kubectl get ns $NAMESPACE --show-labels
KUBECONFIG=$KUBECONFIG kubectl get policyreport -n $NAMESPACE
```

If Application is not Healthy within 5 minutes, suggest `/gitops-health-triage` for diagnosis.
Confirm: namespace exists with correct PNI labels, no Kyverno policy violations in PolicyReport.

## Hard Rules

- Phase 1 is planning only — no Write or Edit tools until after Phase 2 confirmation
- NEVER set provider-reserved labels on consumer namespaces
- NEVER `kubectl apply` ArgoCD-managed resources — git commit + push only
- Do NOT opt `privileged` namespaces into `gateway-backend` (activates default-deny without matching policies)
- Capabilities MUST exist in the registry before consumer opt-in
- AppProject changes must be included in the same commit as the new Application CR — never in a separate commit
