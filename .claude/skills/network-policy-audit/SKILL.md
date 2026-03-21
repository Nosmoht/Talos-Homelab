---
name: network-policy-audit
description: Audit CiliumNetworkPolicies for common mistakes and validate PNI compliance across namespaces. Catches post-DNAT port errors, wrong entity selectors, missing gossip UDP rules, and PNI label violations.
argument-hint: [path-or-namespace|all]
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, Write
---

# Network Policy Audit

Use this skill to lint CiliumNetworkPolicy manifests for known misconfigurations and validate Platform Network Interface (PNI) compliance across namespaces.

## Inputs
- Argument: a path (`kubernetes/overlays/homelab/infrastructure/dex`), a namespace name (`monitoring`), or `all`.

## Workflow

### 1. Resolve targets
- If argument is `all`, scan all directories under `kubernetes/overlays/homelab/` (both `infrastructure/` and `apps/`).
- If argument is a filesystem path, scan that path directly.
- If argument is a namespace name, locate the corresponding overlay directory under `kubernetes/overlays/homelab/`.

### 2. Collect manifests
For each target directory, read:
- All CNP/CCNP files (`cnp-*.yaml`, `ccnp-*.yaml`, and any file containing `kind: CiliumNetworkPolicy` or `kind: CiliumClusterwideNetworkPolicy`).
- Namespace manifests (`namespace.yaml` or files containing `kind: Namespace`).
- ServiceMonitor manifests (for sidecar port cross-referencing).
- Kustomization files (to understand what is included).

### 3. Run CNP lint checks

#### 3a. Post-DNAT kube-apiserver port
Search for `toEntities: ["kube-apiserver"]` or `toEntities: [kube-apiserver]` with `port: "443"` or `port: 443`.
- **ERROR**: Must use port `6443` — Cilium kube-proxy replacement DNATs `ClusterIP 10.96.0.1:443` to `endpoint:6443` before policy evaluation.

#### 3b. Wrong entity for Gateway traffic
Search for `fromEntities: ["world"]` or `fromEntities: [world]` in ingress rules on pods receiving Gateway API traffic.
- **ERROR**: Must use `fromEntities: ["ingress"]` — Cilium external Envoy proxy uses `reserved:ingress` identity (ID 8), not `world`.

#### 3c. Gossip ports missing UDP
Search for gossip-related ports:
- Port `9094` (Alertmanager memberlist) — must have both TCP and UDP.
- Port `7946` (general memberlist/gossip) — must have both TCP and UDP.
- **ERROR** if only `protocol: TCP` or no protocol specified (defaults to TCP).

#### 3d. ServiceMonitor sidecar ports
For each namespace with CNPs, find ServiceMonitors and extract all endpoint ports (e.g., `reloader-web:8080` on alertmanager config-reloader).
- **WARNING** if a ServiceMonitor declares a port not covered by any CNP ingress rule in the same namespace.

#### 3e. CNPs targeting hostNetwork pods
Identify CNP `endpointSelector` labels that match pods known to use `hostNetwork: true` (e.g., `linstor-csi-node`, Cilium agent, `kube-proxy`).
- **WARNING**: CNPs are ineffective on hostNetwork pods — they carry host identity.

#### 3f. K8s NetworkPolicy + CNP AND-semantics conflict
Search for both `kind: NetworkPolicy` (K8s native) and `kind: CiliumNetworkPolicy` selecting the same pods in the same namespace.
- **WARNING**: When both policy types select the same pod, traffic must be allowed by BOTH. This causes unexpected denials.

#### 3g. DRBD port range without endPort
Search for port `7000` (or any port in 7000-7999 range) in rules related to DRBD/LINSTOR without `endPort: 7999`.
- **ERROR**: LINSTOR assigns per-resource ports in 7000-7999; single port rules miss replicated traffic.

#### 3h. Missing DNS egress
For each CNP with egress rules, check whether a DNS egress rule to `kube-dns` (port 53 UDP+TCP, namespace `kube-system`) exists either in the same CNP or another CNP in the namespace.
- **WARNING**: Egress-restricted pods without DNS access will fail name resolution silently.
- If a DNS egress rule specifies port 53 with only `protocol: TCP` and no matching UDP rule for port 53, flag as **ERROR**: DNS primarily uses UDP; TCP-only port 53 causes silent resolution failures for standard queries.

### 4. Run PNI compliance checks

#### 4a. Namespace PNI labels
Check namespace manifests for required labels:
- `platform.io/network-interface-version: v1`
- `platform.io/network-profile` with value `restricted`, `managed`, or `privileged`
- **ERROR** if missing on any non-system namespace.

#### 4b. Capability opt-in validation
Check `platform.io/consume.<capability>: "true"` labels against actual service dependencies visible in CNP egress rules.
- **WARNING** if a CNP references a service that should be covered by a PNI capability but no corresponding `consume.<capability>` label exists.

#### 4c. Provider-reserved labels in consumer namespaces
Search for `platform.io/provider`, `platform.io/managed-by`, or `platform.io/capability` labels in consumer namespace manifests.
- **ERROR**: These are platform-owned labels and must not appear in consumer namespaces.

#### 4d. Capability catalog reference
Read `docs/platform-network-interface.md` and extract the capability catalog. Verify that all `consume.<capability>` labels reference entries that exist in the catalog.
- **WARNING** if a capability label references a non-existent catalog entry.

#### 4e. PNI redundancy detection
Compare CNP rules against PNI-provided CiliumClusterwideNetworkPolicy rules. Flag CNP rules that duplicate connectivity already granted by CCNP rules derived from PNI labels.
- **INFO**: Redundant rule — this connectivity is already provided by PNI CCNP `<name>`.

### 5. Report findings

#### Quick check (fewer than 10 findings)
Print an inline summary grouped by namespace/component, then by severity.

#### Full audit (10 or more findings)
Write `docs/network-policy-audit-<scope>-<yyyy-mm-dd>.md` with the full report.

## Output format

```
## <namespace/component>

### ERRORS
- [CNP-DNAT] cnp-foo.yaml:L42 — toEntities kube-apiserver uses port 443, must be 6443
- [PNI-RESERVED] namespace.yaml:L8 — provider-reserved label platform.io/provider found

### WARNINGS
- [CNP-SIDECAR] cnp-alertmanager.yaml — missing ingress for reloader-web:8080 (from ServiceMonitor)
- [CNP-DNS] cnp-egress.yaml — no DNS egress rule found in namespace

### INFO
- [PNI-REDUNDANT] cnp-monitoring.yaml:L15 — rule duplicates CCNP pni-monitoring-prometheus
```

Severity levels:
- **ERROR** — must fix; causes traffic drops or policy violations.
- **WARNING** — should fix; likely causes issues under certain conditions.
- **INFO** — suggestion; cleanup or optimization opportunity.

## Hard Rules
- Do not propose wildcard allow-all policies as fixes.
- Do not modify any manifests — this skill is read-only audit.
- Always cross-reference `docs/platform-network-interface.md` for PNI checks.
- When reporting sidecar port gaps, include the exact ServiceMonitor name and port spec as evidence.
