---
name: plan-talos-upgrade
description: Build a repo-specific Talos upgrade and migration plan for this homelab cluster by resolving current and target Talos versions, reading all intermediate release notes and upgrade guidance, identifying cluster-specific risks, and saving a reviewed draft plan for manual approval.
argument-hint: [from-version] [to-version]
allowed-tools: Bash, Read, Grep, Glob, Write
---

# Plan Talos Upgrade

Use this skill when asked to plan a Talos upgrade for this cluster. This skill produces a migration plan only. It does not upgrade nodes unless the user explicitly asks for execution afterward.

## Inputs
- Optional `from-version`
- Optional `to-version`

Argument handling:
- two arguments: treat them as `from-version` then `to-version`
- one argument: treat it as `to-version`; resolve `from-version` from the running cluster
- zero arguments: resolve both versions automatically

Examples:
```text
plan-talos-upgrade 1.12.4 1.12.6
plan-talos-upgrade 1.13.0   # interpreted as to-version
plan-talos-upgrade
```

## Bash Usage Constraints
Bash is permitted ONLY for read-only operations during planning:
- `talosctl get` / `talosctl version` / `talosctl disks` / `talosctl health` / `talosctl etcd members` (cluster queries)
- `curl` / `wget` (fetching upstream release metadata)
- `git log` / `git diff` / `git status` (repo history)
- `make -C talos dry-run-*` / `make -C talos validate-generated` (validation only)
Do NOT run any mutating commands (`talosctl upgrade`, `talosctl apply-config`, `kubectl drain`, `kubectl delete`, `make apply-*`, `make upgrade-*`) during planning.

## Repository Facts You Must Respect
- Talos version intent is pinned in `talos/versions.mk` as `TALOS_VERSION := ...`.
- Node install images are derived from `talos/.schematic-ids.mk` and `TALOS_VERSION` in `talos/Makefile`.
- Cluster-wide Talos upgrades run one node at a time through `make -C talos upgrade-<node>`.
- Changes to boot args or extensions may require `make -C talos schematics` before node upgrades.
- `talosctl apply-config --dry-run` and manual operations must use explicit node endpoints, not the VIP, when reliability matters.
- Do not edit `talos/generated/**` directly.
- Do not mix Talos upgrades with unrelated repo changes.

## Required Outcome
Produce a comprehensive upgrade plan that includes:
1. resolved source and target Talos versions, with how each was determined
2. all intermediate Talos releases in semver order
3. a concise summary of important changes per release
4. breaking changes, migration requirements, deprecations, and operator actions
5. cluster-specific impact analysis for this repo, hardware mix, and runtime
6. a staged execution plan with validation, sequencing, and recovery considerations
7. explicit risks, blockers, and open questions
8. a self-review section performed before the final plan is presented
9. a saved plan file under `docs/` with approval metadata initialized to `draft`

## Workflow

### 1. Load repo context first
Read at minimum:
- `CLAUDE.md`
- `README.md`
- `docs/day2-operations.md`
- `talos/Makefile`
- `talos/versions.mk`
- `talos/patches/common.yaml`
- `talos/patches/controlplane.yaml`
- `talos/patches/worker-gpu.yaml`
- `talos/talos-factory-schematic.yaml`
- `talos/talos-factory-schematic-gpu.yaml`
- `talos/talos-factory-schematic-pi.yaml`

Search for Talos-sensitive features and operational dependencies with `rg` before writing the plan.

Extract and record:
- repo-pinned Talos version from `talos/versions.mk`
- Kubernetes and Cilium versions pinned alongside Talos
- node inventory, roles, and upgrade order from `talos/Makefile` and docs
- whether current patches imply install image, kernel argument, or extension changes
- whether any schematic files or patch files changed semantics across the target version hop
- whether `talos/patches/controlplane.yaml` `extraManifests` cache-busting behavior introduces coupled Cilium work
- operational constraints around DRBD, GPU node handling, Pi node handling, and control-plane health

### 2. Resolve `from-version`
If `from-version` was provided, normalize it to `major.minor.patch` and use it.

If omitted, resolve in this order:
1. query the running cluster for the deployed Talos version
2. compare that result with `talos/versions.mk`
3. if they differ, treat that as drift and include it as a first-class risk
4. if the cluster is unreachable, fail closed instead of guessing, unless the user explicitly allows repo-only planning

Preferred live checks:
```bash
talosctl -n 192.168.2.61 -e 192.168.2.61 version
talosctl -n 192.168.2.62 -e 192.168.2.62 version
talosctl -n 192.168.2.63 -e 192.168.2.63 version
kubectl get nodes -o wide
```

Use `talosctl version` against at least one control-plane node as the primary source. If nodes differ, record the skew and stop treating the cluster as a clean baseline.

### 3. Resolve `to-version`
If `to-version` was provided, normalize it to `major.minor.patch` and use it.

If omitted:
1. resolve the latest stable Talos release from the upstream releases page or API
2. exclude pre-releases and release candidates
3. if multiple stable artifacts exist, pick the highest semantic version

Record the exact release URL used for the decision.

### 4. Validate the version hop
Before reading release notes, check:
- `from-version` exists and is not newer than `to-version`
- no downgrade is being planned
- whether the hop crosses one or more minor versions
- whether the hop crosses a major version
- whether the target Talos release supports the repo’s target Kubernetes version
- whether Cilium or bootstrap workflows are coupled to the Talos hop

At minimum, inspect upstream compatibility and upgrade guidance for:
- supported Kubernetes versions
- changed kernel, containerd, kubelet, or bootstrap behaviors
- changed image factory, schematic, or extension mechanics
- changed config schema or deprecated machine configuration fields
- upgrade-order constraints for control-plane nodes and etcd

If the user requested a large skip, call that out explicitly and recommend a staged path if upstream guidance suggests it.

### 5. Read every intermediate release note
Read the release notes and upgrade notes for every version `> from-version` and `<= to-version`.

Rules:
- include patch releases, not only minors
- use semver sorting
- prefer upstream Talos release notes plus linked migration or upgrade docs
- if a release note points to a dedicated upgrade guide, read that guide too
- track source links for every non-trivial claim

Capture per release:
- new requirements or compatibility windows
- breaking changes and changed defaults
- deprecated or removed config fields, flags, extensions, or commands
- changes affecting machine config generation or install images
- changes affecting reboot behavior, etcd, kubelet, networking, or observability
- operational prerequisites and post-upgrade actions

### 6. Perform cluster-specific impact analysis
Do not stop at upstream notes. Map them onto this repo and live cluster.

Check at least:
- `talos/versions.mk`
- `talos/Makefile` image construction and node ordering
- schematic files for standard, GPU, and Pi nodes
- Talos patch files that may interact with version-specific schema or defaults
- control-plane patch coupling to Kubernetes, Cilium, Gateway API, and observability
- whether `talos/patches/controlplane.yaml` `extraManifests` URLs or `?v=` query parameters need coordinated updates
- repo-documented gotchas around DRBD shutdown hangs, etcd recovery, CSR approval, and direct endpoint requirements

Also check for upgrade blast radius:
- etcd quorum loss during control-plane upgrade
- CNI and API reachability after control-plane and worker reboots
- DRBD-backed storage risk during node reboots
- GPU or Pi node image path divergence
- kubelet CSR or bootstrap token issues after reboot
- generated config drift caused by version variable changes

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
1. preflight checks, including:
   - etcd snapshot: `talosctl -n 192.168.2.61 -e 192.168.2.61 etcd snapshot /tmp/etcd-backup-<date>.snapshot`
   - verify snapshot file size is non-zero before proceeding
   - confirm `talosctl version --client` matches or exceeds the target Talos version
2. repo changes required before rollout
3. config generation and validation
4. commit/push expectations
5. node-by-node upgrade sequencing
6. per-node and per-stage verification
7. contingency actions and stop conditions

Use repo-accurate commands where relevant, for example:
```bash
make -C talos schematics
make -C talos gen-configs
make -C talos validate-generated
make -C talos dry-run-node-01
make -C talos upgrade-node-01
talosctl -n 192.168.2.61 -e 192.168.2.61 health --control-plane-nodes 192.168.2.61,192.168.2.62,192.168.2.63
kubectl get nodes -o wide
kubectl -n kube-system get pods -l k8s-app=cilium
kubectl linstor node list
```

Require the plan to address:
- whether `TALOS_VERSION` alone changes, or whether Kubernetes/Cilium/schematics also change
- whether `make -C talos schematics` is required before config generation
- whether coupled Cilium work requires updating `talos/patches/controlplane.yaml` `?v=` and re-rendering bootstrap Cilium manifests
- control-plane order `node-01 -> node-02 -> node-03`
- worker order `node-04 -> node-05 -> node-06 -> node-gpu-01 -> node-pi-01`
- health gates before proceeding to the next node

### 8. Include rollback and safety constraints
Always address:
- whether downgrade is supported, unsupported, or materially risky
- how to preserve the pre-upgrade repo version pins and schematic IDs
- what health signals must be green before moving to the next node
- what to do if a node is stuck shutting down, fails to rejoin etcd, or loses networking
- what to do if kubelet CSR approval or Cilium recovery blocks readiness

Never pretend rollback is symmetric if it requires disruptive re-imaging, reset flows, or other exceptional recovery.

### 9. Review before presenting
Critically review the draft plan before returning it.

Review checklist:
- every version between source and target was covered
- target release is truly stable, not RC or beta
- live cluster version and repo pin were compared
- Kubernetes compatibility and coupled version impacts were checked
- upgrade risks were mapped to this cluster’s hardware, storage, and control-plane topology
- commands align with this repo’s Talos and GitOps operating model
- no step relies on forbidden practices from `CLAUDE.md`
- every major recommendation has at least one cited upstream source
- blockers and unknowns are explicit rather than hidden

If the review finds gaps, fix them before presenting the final plan. Do not present the unreviewed draft.

### 10. Save the reviewed plan as a draft artifact
After the plan passes self-review, write it to:
- `docs/talos-upgrade-plan-<from-version>-to-<to-version>-<yyyy-mm-dd>.md`

The file must begin with this frontmatter shape:
```yaml
---
plan_source: plan-talos-upgrade
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
- If upstream release information cannot be retrieved, do not guess the target version.
- If the repo or running cluster shows unsupported skew, elevate that to a blocker.
- If the release notes are incomplete, say what was missing and what source was used instead.
