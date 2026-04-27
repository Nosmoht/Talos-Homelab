# ADR: Multi-Repo Platform Split for Multi-Cluster Reuse

**Status**: Proposed (review pending)
**Date**: 2026-04-27
**Supersedes**: implicit single-repo assumption in #66, #67, #84

## Context

This repository began as a single-cluster homelab GitOps tree. With the addition
of a second cluster (`office-lab`, corporate site, internal-only, 3 control-plane
+ 4 worker, no GPU, no WAN edge), the single-overlay / single-repo model becomes
insufficient:

1. Cluster identity (IPs, FQDNs, OIDC issuers, SOPS keys) is hardcoded in
   56+ files across `kubernetes/overlays/homelab/**`, making add-cluster a
   copy-paste exercise that drifts over time.
2. Tooling (28 skills, 6 agents, 7 hooks, 9 scripts) lives in `.claude/**`
   of this repo, but should be reused across both clusters without manual sync.
3. Issues #66 (cross-cluster trust model) and #67 (multi-cluster service
   consumption / PNI evolution) require an explicit federation model before
   further architectural commitment.

## Decision

Split the platform into **three logically distinct repositories**, with the
existing repo evolving into the base layer and history preserved via
`git filter-repo`:

| Repo (target name) | Owner | Visibility | Contents |
|---|---|---|---|
| **`talos-platform-base`** (current Talos-Homelab repo, renamed) | Nosmoht | personal | Talos templates, Cilium/Piraeus/KubeVirt/Kyverno/cert-manager Helm bases, ArgoCD bootstrap (parameterized), AGENTS.md core constraints. NO cluster identity. |
| **`kube-agent-harness`** (existing private repo, reused as plugin) | devobagmbh | private | `.claude/{skills,agents,rules,references,hooks}` extracted from current repo + existing harness content. Acts as Claude-Code plugin for both cluster repos. |
| **`talos-homelab-cluster`** (new repo via filter-repo) | Nosmoht | personal | `kubernetes/overlays/homelab/**`, `talos/nodes/`, `.claude/environment.yaml`, homelab-specific ADRs. Consumes base + plugin. |
| **`talos-office-lab-cluster`** (new repo, scaffold from template) | corporate / devobagmbh | private | Office-lab cluster identity. Consumes base + plugin. |

**Per-cluster trust model** (resolves #66): Each cluster is a self-rooted peer.
No shared CA, no shared SOPS key, no shared Vault. Per-cluster break-glass
kubeconfig.

**Per-cluster service consumption** (resolves #67): All capabilities are
cluster-local. The "shared platform service" class is intentionally empty.
PNI labels remain cluster-scoped.

**Codex CLI is no longer a primary support target for skills.** Claude Code's
plugin mechanism (project-level `claude plugin install` + global
`~/.claude/plugins/`) is the canonical distribution path. Codex users who want
skill access must clone `kube-agent-harness` separately and symlink — manual
fallback only.

## Consequences

### Positive
- Cluster identity isolation matches per-cluster security boundary (per-repo
  SOPS, per-repo CI access, per-repo PR review).
- Skills/agents update once → both clusters benefit.
- Adding cluster N+1 = scaffold from template + per-cluster repo; no base-repo
  edits.
- Aligns with industry GitOps-fleet patterns (Flux fleet-infra, ArgoCD
  ApplicationSet-of-cluster-repos).
- Resolves long-standing Issues #66 and #67 with a concrete trust + consumption
  decision.

### Negative
- 4 repos for 2 clusters = coordination overhead. Bumping a base component
  requires coordinated PRs across 3 repos.
- `git filter-repo` migration is a multi-hour one-way operation per repo. Not
  reversible without manual fixup.
- `kubernetes/base/` and `talos/patches/common.yaml` need a one-time cleanup
  pass to remove hardcoded homelab IPs before the base repo is truly
  cluster-agnostic.
- AGENTS.md / CLAUDE.md split requires careful import structure (host repo
  `@`-imports plugin docs).
- Codex CLI user experience for skills degrades to "manual symlink".

### Neutral / Out of scope
- ArgoCD ApplicationSet-of-clusters not adopted — each cluster runs its own
  ArgoCD pointing at its own repo. Manageable for ≤5 clusters.
- Service mesh federation explicitly NOT planned.
- Cross-cluster Vault/Dex/SSO explicitly NOT planned.

## Migration Plan (Phases)

### Phase 1 — Base de-homelab-ification (in current repo, ~1 week)
- Move hardcoded NTP/gateway from `talos/patches/common.yaml` into per-cluster
  patch.
- Parameterize `talos/Makefile` (`CLUSTER ?= homelab`, per-cluster
  `clusters/<name>.mk`).
- Parameterize `kubernetes/bootstrap/argocd/` (`OVERLAY ?= homelab`,
  `REPO_URL ?= ...`).
- Extract any cluster-specific Helm values that leaked into
  `kubernetes/base/infrastructure/**/values.yaml` into the homelab overlay.

### Phase 2 — Plugin extraction (~1 week)
- `git filter-repo --path .claude/skills/ --path .claude/agents/ --path .claude/rules/ --path .claude/references/ --path .claude/hooks/`
  → integrate into `kube-agent-harness`.
- Replace `.claude/**` in current repo with plugin reference
  (`claude plugin install kube-agent-harness` or equivalent).
- Update CLAUDE.md / AGENTS.md to document the new plugin source.

### Phase 3 — Cluster split + office-lab scaffold (~2 weeks)
- 3A: `git filter-repo --path kubernetes/overlays/homelab --path talos/nodes --path talos/patches/pi-firewall.yaml --path docs/adr-pi-sole-public-ingress.md ...`
  → new `talos-homelab-cluster` repo.
- 3B: Rename current repo to `talos-platform-base`. Final cleanup.
- 3C: Scaffold `talos-office-lab-cluster` from base. Deliver network admin brief.

### Verification gate (Phase 3 done)
- Existing homelab cluster still reconciled by ArgoCD from new homelab-cluster
  repo (no production drift during migration).
- Office-lab can be brought up from base + plugin + new office-lab repo using
  the same workflow.

## Alternatives Considered

| Alternative | Why rejected |
|---|---|
| Multiple overlays in single repo (`overlays/homelab/`, `overlays/office-lab/`) | User explicitly judged unrealistic — too many homelab-specific concerns leak through cluster boundary; access control is per-repo on GitHub. |
| ArgoCD ApplicationSet-of-clusters in one repo | Same coupling concerns. ApplicationSet pattern works well at scale (≥10 clusters); for 2 clusters it's overkill and bundles unrelated trust domains. |
| Helm values branching per cluster | Doesn't address Talos node-config separation, doesn't address SOPS-key per-cluster, doesn't address PR-review boundary. |
| Keep monolith, defer multi-cluster | Postpones the problem; office-lab bringup blocks on this anyway. |

## References
- Issues: #66 (cross-cluster trust), #67 (multi-cluster service consumption),
  #84 (Claude harness primitives epic), #142 (closed — recent CI work that
  established the pattern of issue-driven changes)
- Memory: `feedback_harness_composition.md`, `feedback_harness_capability_driven.md`,
  `reference_harness_service_model.md`, `project_multi_repo_split_decided.md`
- External: ArgoCD ApplicationSet patterns
  (https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/),
  Flux fleet-infra reference architecture
  (https://github.com/fluxcd/flux2-multi-tenancy)
