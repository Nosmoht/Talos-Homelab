---
name: plan-cilium-upgrade
description: Build a repo-specific Cilium upgrade and migration plan for this homelab cluster by resolving current and target versions, reading all intermediate release notes, identifying breaking changes and risks, and reviewing the plan before presenting it.
argument-hint: [from-version] [to-version]
allowed-tools: Bash, Read, Grep, Glob, Write, WebSearch, WebFetch
---

# Plan Cilium Upgrade

Use this skill when asked to plan a Cilium upgrade for this cluster. This skill produces a migration plan only. It does not roll out the upgrade unless the user explicitly asks for execution afterward.

## Inputs
- Optional `from-version`
- Optional `to-version`

Argument handling:
- two arguments: treat them as `from-version` then `to-version`
- one argument: treat it as `to-version`; resolve `from-version` from the running cluster
- zero arguments: resolve both versions automatically

Examples:
```text
plan-cilium-upgrade 1.18.3 1.19.0
plan-cilium-upgrade 1.19.2   # interpreted as to-version
plan-cilium-upgrade
```

## Repository Facts You Must Respect
- Cilium is bootstrap-managed from `kubernetes/bootstrap/cilium/cilium.yaml`.
- Talos control plane nodes consume that manifest through `talos/patches/controlplane.yaml` `extraManifests`.
- Version intent is pinned in `talos/versions.mk` as `CILIUM_VERSION := ...`.
- Do not propose `kubectl apply` for Argo CD-managed rollout work.
- Do not propose ad-hoc `kubectl apply` drift fixes for `kubernetes/bootstrap/cilium/cilium.yaml`; reconcile through the Talos workflow.

## Required Outcome
Produce a comprehensive upgrade plan that includes:
1. resolved source and target versions, with how each was determined
2. all intermediate Cilium releases in semver order
3. a concise summary of important changes per release
4. breaking changes, deprecations, default flips, and migration actions
5. cluster-specific impact analysis for this repo and runtime
6. a staged execution plan with validation and rollback considerations
7. explicit risks, blockers, and open questions
8. a self-review section performed before the final plan is presented
9. a saved plan file under `docs/` with approval metadata initialized to `draft`

### Example Output Fragment
```markdown
### Version Resolution
- **From:** v1.15.3 (cluster) / v1.15.3 (repo pin) — no drift
- **To:** v1.16.1 (latest stable)
- **Hop:** 1.15 → 1.16 (single minor, valid)

### Breaking Changes
| Release | Change | Cluster Impact | Action Required |
|---------|--------|---------------|-----------------|
| v1.16.0 | Deprecated `--enable-legacy-host-routing` | Using kube-proxy replacement — affected | Update bootstrap values before upgrade |
```

## Workflow

### 1. Load repo context first
Read at minimum:
- `CLAUDE.md`
- `README.md`
- `talos/versions.mk`
- `talos/patches/controlplane.yaml`
- `.claude/rules/cilium-gateway-api.md`
- `docs/day2-operations.md`

Then inspect the current bootstrap manifest:
- `kubernetes/bootstrap/cilium/cilium.yaml`

Extract and record:
- repo-pinned Cilium version from `talos/versions.mk`
- whether the bootstrap manifest embeds chart/image labels that imply a different version
- enabled Cilium features that increase upgrade risk, including:
  - Gateway API / Envoy
  - Hubble
  - kube-proxy replacement / socket LB / routing mode
  - L2 announcements, LB IPAM, BGP, or external IP features
  - encryption, ClusterMesh, local redirect, host firewall, CNI chaining, or any non-default datapath modes
- any repo-managed `cilium.io/*` resources outside the bootstrap manifest

Search for Cilium dependencies and managed resources with `rg` before writing the plan.

### 2. Resolve `from-version`
If `from-version` was provided, normalize it to `major.minor.patch` and use it.

If omitted, resolve in this order:
1. query the running cluster for the deployed Cilium version
2. compare that result with `talos/versions.mk`
3. if they differ, treat that as drift and include it as a first-class risk
4. if the cluster is unreachable, fail closed instead of guessing, unless the user explicitly allows repo-only planning

Preferred live checks:
```bash
KUBECONFIG=/tmp/homelab-kubeconfig kubectl -n kube-system get ds cilium -o json
KUBECONFIG=/tmp/homelab-kubeconfig kubectl -n kube-system get deploy cilium-operator -o json
KUBECONFIG=/tmp/homelab-kubeconfig kubectl -n kube-system get cm cilium-config -o yaml
KUBECONFIG=/tmp/homelab-kubeconfig cilium version
```

Use the daemonset image tag or `cilium version` output as the primary source. Do not rely only on labels.

### 3. Resolve `to-version`
If `to-version` was provided, normalize it to `major.minor.patch` and use it.

If omitted:
1. query `https://github.com/cilium/cilium/releases` or the GitHub releases API
2. choose the latest stable release
3. exclude pre-releases and release candidates
4. if multiple stable artifacts exist, pick the highest semantic version

Record the exact release URL used for the decision.

### 4. Validate the version hop
Before reading release notes, check:
- `from-version` exists and is not newer than `to-version`
- no downgrade is being planned
- whether the hop crosses one or more minor versions — **if the hop spans more than one minor version**, flag this explicitly. Cilium only supports consecutive minor releases for upgrade and rollback. Recommend a staged path (e.g., 1.16 → 1.17 → 1.18). See `references/cilium-upgrade-constraints.md`.
- whether the hop crosses a major version
- whether the repo’s Talos and Kubernetes versions are compatible with the target Cilium release (see compatibility matrix in `references/cilium-upgrade-constraints.md`)

At minimum, inspect Cilium’s documented compatibility notes for:
- supported Kubernetes versions
- kernel, eBPF, Envoy, and Hubble caveats
- Gateway API support changes

If the user requested a large skip, call that out explicitly and consider recommending a staged upgrade path if upstream guidance suggests it.

### 5. Read every intermediate release note
Read the release notes for every version `> from-version` and `<= to-version`.

Rules:
- include patch releases, not only minors
- use semver sorting
- prefer GitHub release notes plus linked upgrade or migration guides when referenced
- if a release note points to a dedicated upgrade guide, read that guide too
- track source links for every non-trivial claim

Capture per release:
- new requirements or compatibility windows
- breaking changes
- deprecated and removed flags, Helm values, CRDs, APIs, annotations, and metrics
- data-plane, control-plane, and observability changes
- operational prerequisites and post-upgrade actions

### 6. Perform cluster-specific impact analysis
Do not stop at upstream notes. Map them onto this repo and live cluster.

Check at least:
- Cilium feature flags in `kubernetes/bootstrap/cilium/cilium.yaml`
- Talos-managed bootstrap coupling through `extraManifests`
- Gateway API resources under `kubernetes/**/gateway-api/**`
- Hubble dashboards, ServiceMonitors, and policy-debug workflows in docs and manifests
- any `CiliumNetworkPolicy`, `CiliumClusterwideNetworkPolicy`, `CiliumLoadBalancerIPPool`, `CiliumL2AnnouncementPolicy`, `GatewayClass`, `Gateway`, `HTTPRoute`, or Envoy-related resources
- whether the running cluster has objects or flags that no longer exist in the target version
- whether the repo pins chart fields that changed semantics upstream

Also check for upgrade blast radius:
- control plane reachability during CNI restart
- service VIP continuity and Gateway API ingress disruption
- policy enforcement regressions
- Hubble relay or UI version skew
- metrics/dashboards/query drift

### 7. Build the migration plan
The plan must be execution-ready and ordered.

Include these sections:
- `Version Resolution`
- `Intermediate Releases Reviewed`
- `Cluster-Specific Findings`
- `Breaking Changes and Required Migrations`
- `Execution Plan`
- `Validation Plan`
- `Rollback and Recovery`
- `Risks and Open Questions`
- `Self-Review`

The execution plan must cover:
1. preflight checks (including `cilium preflight check` — see `references/cilium-upgrade-constraints.md`)
2. repo changes required before rollout — **never use `--reuse-values` when upgrading Cilium Helm charts** (silently drops new required values; see constraints reference)
3. validation of rendered manifests
4. commit/push expectations
5. node or cluster upgrade sequencing through the Talos workflow when required
6. post-upgrade verification
7. contingency actions

Use repo-accurate commands where relevant, for example:
```bash
make -C talos cilium-bootstrap
make -C talos cilium-bootstrap-check
make -C talos gen-configs
make -C talos dry-run-all
make -C talos upgrade-k8s
make -C talos upgrade-node-01
kubectl -n kube-system get pods -l k8s-app=cilium
kubectl get ciliumnode
```

If the version bump changes `CILIUM_VERSION`, require the plan to address:
- regeneration of `kubernetes/bootstrap/cilium/cilium.yaml` via `make -C talos cilium-bootstrap`
- validation via `make -C talos cilium-bootstrap-check`
- reconciliation of Talos `extraManifests` state through the repo’s supported Talos workflow, including `make -C talos upgrade-k8s` when the plan depends on re-applying control-plane `extraManifests`

Do not imply that editing `kubernetes/bootstrap/cilium/cilium.yaml` alone completes rollout.

### 8. Include rollback and safety constraints
Always address:
- whether downgrade is supported or effectively unsupported
- how to preserve a copy of the pre-upgrade bootstrap manifest and repo version pin
- what health signals must be green before moving to the next node
- what to do if Cilium pods do not recover, Gateway traffic fails, or policy drops spike
- whether Talos node-by-node progression is required

Never recommend a rollback path that depends on direct apply drift against repo-owned steady state without making that tradeoff explicit.

### 9. Review before presenting
Critically review the draft plan before returning it.

Review checklist:
- every version between source and target was covered
- target release is truly stable, not RC or beta
- live cluster version and repo pin were compared
- Kubernetes and Talos compatibility were checked
- upgrade risks were mapped to this cluster’s enabled Cilium features
- commands align with this repo’s GitOps and Talos operating model
- no step relies on forbidden practices from `CLAUDE.md`
- every major recommendation has at least one cited upstream source
- blockers and unknowns are explicit rather than hidden

If the review finds gaps, fix them before presenting the final plan. Do not present the unreviewed draft.

### 10. Save the reviewed plan as a draft artifact
After the plan passes self-review, write it to:
- `docs/cilium-upgrade-plan-<from-version>-to-<to-version>-<yyyy-mm-dd>.md`

The file must begin with this frontmatter shape:
```yaml
---
plan_source: plan-cilium-upgrade
from_version: <from-version>
to_version: <to-version>
generated_at: <yyyy-mm-dd>
status: draft
approved_by:
approved_at:
---
```

Rules:
- `status` must be `draft` when the planning skill writes the file
- never mark the plan as approved automatically
- `approved_by` and `approved_at` must be left empty by the planning skill
- the body below the frontmatter must contain the reviewed plan using the required output sections

### 11. Tell the operator how to approve the plan
At the end of the response, instruct the operator to approve the plan by manually editing the frontmatter in the saved file:
```yaml
status: approved
approved_by: <operator-name>
approved_at: <yyyy-mm-dd>
```

Do not treat chat approval as sufficient. The approval lives in the plan file.

## Output Format
Write the reviewed plan file first, then present a concise summary in chat.

The saved plan file must contain these sections (matching the required plan structure):
- `Version Resolution`
- `Intermediate Releases Reviewed`
- `Cluster-Specific Findings`
- `Breaking Changes and Required Migrations`
- `Execution Plan`
- `Validation Plan`
- `Rollback and Recovery`
- `Risks and Open Questions`
- `Self-Review`

For `Reviewed Releases`, list each version with source links.

For `Self-Review`, state:
- what was checked
- what was uncertain
- whether the plan is safe to execute as written or needs more investigation

In the chat response, also include:
- the saved plan path
- that the plan is currently `draft`
- the exact frontmatter fields the operator must edit to approve it

## Failure Modes
- If cluster access is required to resolve `from-version` and it is unavailable, state that clearly and stop unless the user accepts repo-only planning.
- If GitHub release information cannot be retrieved, do not guess the target version.
- If the repo or running cluster shows unsupported skew, elevate that to a blocker.
- If the release notes are incomplete, say what was missing and what source was used instead.
