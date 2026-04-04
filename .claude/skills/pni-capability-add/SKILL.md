---
name: pni-capability-add
description: "Add a PNI capability: author CCNP, register in ConfigMap, update Kyverno allowlist, update docs — as one atomic commit. Use when onboarding new platform services."
argument-hint: "<capability-name> --provider <ns/component> --type egress|ingress|api-only"
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, Write, Edit
---

# PNI Capability Add

## Environment Setup

Read `.claude/environment.yaml` for kubeconfig path.
If the file is missing, stop: "Copy `.claude/environment.example.yaml` to `.claude/environment.yaml` and fill in your cluster details."

## Reference Files

Read before acting:
- `docs/platform-network-interface.md` — capability catalog, CCNP patterns, API-only table, onboarding workflow
- `.claude/rules/cilium-network-policy.md` — CCNP naming conventions, identity selectors, post-DNAT ports
- `kubernetes/overlays/homelab/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml` — current registry (must update)
- `kubernetes/overlays/homelab/infrastructure/platform-network-interface/resources/kyverno-clusterpolicy-pni-capability-validation-enforce.yaml` — current allowlist (must update)

Also read 2-3 existing CCNPs as examples:
```bash
ls kubernetes/overlays/homelab/infrastructure/platform-network-interface/resources/ccnp-pni-*.yaml
```
Read each one to understand the selector and port patterns.

## Inputs

- `<capability-name>`: Name of the new capability (kebab-case, e.g., `tetragon-export`)
- `--provider <ns/component>`: Provider namespace and component (e.g., `tetragon/tetragon-agent`)
- `--type egress|ingress|api-only`: Capability type

## Scope Guard

If the user wants to onboard a CONSUMER namespace (not add a new capability):
- Suggest `/onboard-workload-namespace` instead.

If the user wants to debug a CNP traffic drop:
- Suggest `/cilium-policy-debug` instead.

If the capability already exists in `capability-registry-configmap.yaml`:
- Stop and report: "Capability '<name>' already registered. To modify it, edit the existing CCNP and update docs/platform-network-interface.md."

## Workflow

### 1. Classify capability type

Determine from `--type`:
- `egress`: Consumer namespace initiates traffic TO the platform service. CCNP required.
- `ingress`: Platform service initiates traffic TO consumer namespaces. CCNP required.
- `api-only`: Contract-only (e.g., tls-issuance, storage-csi, logging-ship) — no CCNP needed; only registry + Kyverno + docs entries.

### 2. Author the CCNP (skip for api-only)

File path:
```
kubernetes/overlays/homelab/infrastructure/platform-network-interface/resources/ccnp-pni-<capability>-consumer-<egress|ingress>.yaml
```

Rules:
- Use namespace-label selectors: `k8s:io.cilium.k8s.namespace.labels.platform.io/consume.<capability>: "true"`
- Never encode namespace names or Deployment names in consumer-side selectors
- Include explicit `toPorts` with container ports (post-DNAT, not service ports)
- Apply `app.kubernetes.io/*` recommended labels
- Follow naming from `.claude/rules/cilium-network-policy.md`

### 3. Register in capability registry

Add capability name to `capability-registry-configmap.yaml` under the appropriate section (egress, ingress, or api-only).

### 4. Update Kyverno allowlist

Add capability name to the allowlist array in:
```
kubernetes/overlays/homelab/infrastructure/platform-network-interface/resources/kyverno-clusterpolicy-pni-capability-validation-enforce.yaml
```

Verify the JMESPath expression is syntactically valid (check for balanced brackets and correct array syntax).

### 5. Update documentation

Add a row to the capability table in `docs/platform-network-interface.md`:
- Capability name, type, provider, description, CCNP file (or "N/A" for api-only)

Update the "Current Policy Coverage" section if present.

## User Confirmation Gate

Present all changed files and their diffs for user review before writing:
- CCNP (if applicable): `ccnp-pni-<capability>-consumer-<direction>.yaml`
- Registry: `capability-registry-configmap.yaml` (new entry)
- Kyverno: `kyverno-clusterpolicy-pni-capability-validation-enforce.yaml` (new entry)
- Docs: `docs/platform-network-interface.md` (new table row)

Wait for explicit confirmation before writing.

### 6. Validate

Run:
```bash
make validate-kyverno-policies
kubectl kustomize kubernetes/overlays/homelab > /dev/null
```

If either fails, stop: "Validation failed. See the error above and fix before committing."

### 7. Atomic commit

All changed files MUST be in a single commit:
```bash
git add kubernetes/overlays/homelab/infrastructure/platform-network-interface/resources/ccnp-pni-<capability>-consumer-<direction>.yaml
git add kubernetes/overlays/homelab/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml
git add kubernetes/overlays/homelab/infrastructure/platform-network-interface/resources/kyverno-clusterpolicy-pni-capability-validation-enforce.yaml
git add docs/platform-network-interface.md
git commit -m "feat(pni): add <capability-name> capability"
```

## Hard Rules

- CCNP naming MUST follow: `ccnp-pni-<capability>-consumer-egress.yaml` or `-ingress.yaml`
- Never set provider-reserved labels on consumer selectors (`platform.io/provider`, `platform.io/managed-by`, `platform.io/capability`)
- Do NOT opt `privileged` namespaces into `gateway-backend` or `internet-egress`
- All 4 changes (CCNP, registry, Kyverno, docs) MUST land in a single commit — no partial states
- Never `kubectl apply` directly — these are ArgoCD-managed; git commit + push only
