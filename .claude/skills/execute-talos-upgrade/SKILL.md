---
name: execute-talos-upgrade
description: Execute a reviewed Talos upgrade for this homelab cluster by validating an approved migration plan, updating repo-managed version and schematic inputs, regenerating configs, and performing a gated node-by-node rollout with explicit recovery actions.
argument-hint: <approved-plan-path>
disable-model-invocation: true
allowed-tools: Bash, Read, Grep, Glob, Write
---

# Execute Talos Upgrade

Use this skill only after `plan-talos-upgrade` has produced a reviewed migration plan and that plan has been explicitly approved for execution.

This skill changes live cluster state and reboots nodes. Treat every step as safety-critical.

## Input
- Required argument: path to an approved Markdown plan document.

Preferred location:
- `docs/talos-upgrade-plan-<from>-to-<to>-<yyyy-mm-dd>.md`

The approved plan must follow the output contract from `plan-talos-upgrade`, contain these frontmatter fields, and contain these sections:
- `plan_source: plan-talos-upgrade`
- `from_version: ...`
- `to_version: ...`
- `generated_at: ...`
- `status: approved`
- `approved_by: ...`
- `approved_at: ...`
- `Resolved Versions`
- `Reviewed Releases`
- `Migration Plan`
- `Risks`
- `Self-Review`

If the plan is missing any required field or section, stop. Do not infer missing approval context.

## Repository Facts You Must Respect
- Talos version intent is pinned in `talos/versions.mk`.
- Install images are derived from `talos/.schematic-ids.mk` and `talos/Makefile`.
- Generated machine configs live under `talos/generated/**` and must never be edited directly.
- Cluster-wide upgrades must be done one node at a time with explicit readiness gates.
- Manual Talos operations must use explicit node endpoints.
- If schema, boot args, or extensions change, schematic regeneration may be required before upgrade execution.
- Do not batch this rollout with unrelated repo changes.

## Workflow

### 1. Validate the approved plan artifact
Read:
- the approved plan file passed as the argument
- `CLAUDE.md`
- `README.md`
- `docs/day2-operations.md`
- `talos/Makefile`
- `talos/versions.mk`
- relevant Talos patch and schematic files referenced by the plan

Confirm the plan includes:
- frontmatter `plan_source: plan-talos-upgrade`
- frontmatter `status: approved`
- non-empty frontmatter `approved_by`
- non-empty frontmatter `approved_at`
- a specific `from_version`
- a specific `to_version`
- explicit rollout steps
- explicit risks and stop conditions
- a self-review that does not leave unresolved blockers

Extract from the plan:
- approved `from_version`
- approved `to_version`
- whether schematics must be regenerated
- any required repo edits beyond `TALOS_VERSION`
- whether coupled Cilium work requires `talos/patches/controlplane.yaml` `?v=` changes and `make -C talos cilium-bootstrap`
- any plan-specific validation commands or special cautions

If the plan says more investigation is required before execution, stop.

If the frontmatter `status` is not exactly `approved`, stop.

### 2. Confirm current state still matches the approved plan
Before editing anything, verify that the plan is still fresh.

Check:
- git worktree cleanliness for files involved in the upgrade
- current repo pin in `talos/versions.mk`
- current schematic inputs and IDs if the plan depends on them
- live Talos version across control-plane nodes
- cluster health, etcd health, and node readiness
- Cilium and Kubernetes baseline health before node reboots begin

Run at minimum:
```bash
git status --short
talosctl -n 192.168.2.61 -e 192.168.2.61 version
talosctl -n 192.168.2.62 -e 192.168.2.62 version
talosctl -n 192.168.2.63 -e 192.168.2.63 version
talosctl -n 192.168.2.61 -e 192.168.2.61 health --control-plane-nodes 192.168.2.61,192.168.2.62,192.168.2.63 --worker-nodes 192.168.2.64,192.168.2.65,192.168.2.66,192.168.2.67,192.168.2.68
talosctl -n 192.168.2.61 -e 192.168.2.61 etcd members
kubectl get nodes -o wide
kubectl get pods -A | grep -v Running
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
kubectl linstor node list
kubectl linstor resource list
kubectl linstor resource list --faulty
```

If the live cluster version does not match the plan’s `from_version`, stop and report drift.

If the worktree already contains unrelated changes in files required for the upgrade, stop and resolve that first. Do not mix this rollout with other pending work.

If nodes are NotReady, etcd is unhealthy, DRBD state is risky, or Cilium is already degraded, stop unless the approved plan explicitly covers that degraded starting state.

### 3. Create a pre-change evidence record
Before mutating the repo or cluster, capture baseline evidence for comparison.

Record:
- current git branch and status
- current `TALOS_VERSION`, `KUBERNETES_VERSION`, and `CILIUM_VERSION`
- schematic IDs if present
- Talos version by node
- etcd members and cluster health
- node readiness
- Cilium health and storage health

Write a run record to:
- `docs/talos-upgrade-execution-<from>-to-<to>-<yyyy-mm-dd>.md`

The run record must contain:
1. approved plan path
2. execution timestamp
3. baseline health
4. commands executed
5. results by stage and by node
6. final verification
7. incidents, pauses, or recovery actions

### 4. Apply repo changes from the approved plan
Make only the changes required by the approved plan.

At minimum this usually means:
1. update `talos/versions.mk` `TALOS_VERSION`
2. regenerate schematics if the plan requires it
3. regenerate configs
4. validate generated configs

Required commands when applicable:
```bash
make -C talos schematics
make -C talos cilium-bootstrap
make -C talos cilium-bootstrap-check
make -C talos gen-configs
make -C talos validate-generated
make -C talos dry-run-all
```

If the approved plan includes Kubernetes or Cilium coupling, update and validate those repo changes before continuing. Do not continue with a partially updated repo state.

### 5. Review the repo diff before rollout
Inspect the exact diff and compare it to the approved plan.

Confirm:
- `TALOS_VERSION` changed to the approved target and nothing else changed unintentionally
- schematic or patch changes match the approved plan exactly
- any required `talos/patches/controlplane.yaml` `?v=` bump and bootstrap Cilium regeneration match the approved plan exactly
- generated config changes are consistent with the version hop
- no unrelated files were modified unless the plan required them

If the diff contains unexpected changes, stop and resolve before continuing.

### 6. Commit and push the validated repo state
Once the repo changes are validated:
```bash
git status --short
git add talos/versions.mk talos/.schematic-ids.mk talos/talos-factory-schematic.yaml talos/talos-factory-schematic-gpu.yaml talos/talos-factory-schematic-pi.yaml talos/patches/controlplane.yaml kubernetes/bootstrap/cilium/cilium.yaml
git commit -m "chore(talos): upgrade to <to-version>"
git push
```

Stage only the files actually changed by the approved plan. Do not batch this change with unrelated work.

### 7. Execute the supported rollout path
Use the approved plan’s sequencing. Default order for this repo:
1. `node-01`
2. `node-02`
3. `node-03`
4. `node-04`
5. `node-05`
6. `node-06`
7. `node-gpu-01`
8. `node-pi-01`

For each node:

1. **LINSTOR gate:** `kubectl linstor resource list --faulty` — must be empty before proceeding
2. **Pre-drain** (worker nodes only — skip for control-plane node-01..03; gracefully evicts workloads; the LINSTOR faulty gate in step 1 protects DRBD nodes specifically):
   ```bash
   kubectl drain <node> --delete-emptydir-data --ignore-daemonsets --timeout=120s
   ```
3. **Dry-run and upgrade:**
   ```bash
   make -C talos dry-run-<node>
   make -C talos upgrade-<node>
   ```
4. **Pi node retry** (node-pi-01 only): If the upgrade times out at "waiting for actor ID", retry `talosctl upgrade` directly with `--timeout 15m`. The node remains at pre-upgrade version and Ready — safe to retry.

Wait for health gates to pass before moving to the next node. Do not parallelize node upgrades.

If the approved plan includes a separate Kubernetes or Cilium reconciliation step, follow that exact broader sequencing and do not improvise a shorter path.

If the approved plan includes a coupled Cilium refresh through Talos `extraManifests`, include the repo-supported `make -C talos apply-all && make -C talos upgrade-k8s` sequencing exactly when the approved plan requires it.

### 8. Enforce stage gates during rollout
After each node upgrade, verify health before proceeding.

Minimum per-node health gates:
```bash
kubectl get node <node>
talosctl -n <node-ip> -e <node-ip> version
talosctl -n 192.168.2.61 -e 192.168.2.61 health --control-plane-nodes 192.168.2.61,192.168.2.62,192.168.2.63 --worker-nodes 192.168.2.64,192.168.2.65,192.168.2.66,192.168.2.67,192.168.2.68
talosctl -n 192.168.2.61 -e 192.168.2.61 etcd members
kubectl get nodes -o wide
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
kubectl linstor node list
kubectl linstor resource list --faulty
# Wait up to 5 min for DRBD resync if faulty; investigate if persistent
# Verify node is schedulable:
kubectl get node <node> -o jsonpath='{.spec.unschedulable}'
# If true, run: kubectl uncordon <node>
```

Also run plan-specific verification for:
- API server reachability
- control-plane quorum and learner/voter status
- Cilium recovery and pod networking
- storage/DRBD safety
- GPU or Pi node-specific behavior if applicable
- kubelet CSR handling if a node fails to become Ready automatically

### 9. Stop conditions
Stop immediately if any of the following occur:
- a control-plane node fails to return healthy within the approved threshold
- etcd quorum is degraded or a member fails to rejoin cleanly
- a worker remains NotReady past the approved threshold
- DRBD or LINSTOR health degrades beyond the approved risk boundary
- Cilium fails to recover after a node reboot
- API server or pod networking is broken
- a node is stuck shutting down
- the upgrade sequence is locked (CSI unmount deadlock) — `reboot`, `upgrade --force`, and `reset` all fail with "locked"; requires physical power cycle; node returns at pre-upgrade version and can be retried
- a node retains SchedulingDisabled after upgrade reports success
- unexpected CSR, certificate, or bootstrap issues block readiness

Do not continue “to see if it settles” once a stop condition is met.

### 10. Recovery actions
If a stop condition is met:
1. halt further rollout actions
2. collect diagnostics
3. compare the failure with the approved rollback and recovery guidance
4. choose the least-risk recovery path supported by the plan

Useful diagnostics:
```bash
talosctl -n <node-ip> -e <node-ip> version
talosctl -n <node-ip> -e <node-ip> services
talosctl -n <node-ip> -e <node-ip> dmesg | tail -n 200
talosctl -n 192.168.2.61 -e 192.168.2.61 etcd members
kubectl get csr
kubectl get nodes -o wide
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
kubectl linstor resource list
```

```bash
# If upgrade sequence is locked (CSI unmount deadlock):
# 1. Physical power cycle is the ONLY recovery
# 2. Node boots at pre-upgrade version
# 3. After power cycle: verify health, then retry with kubectl drain first
```

If recovery requires repo reversion:
- revert only the Talos upgrade change set
- regenerate configs
- validate again
- commit and push the reversion
- follow the approved recovery path for node repair or rollback

Do not improvise a downgrade or reset flow unless the approved plan explicitly covers it.

### 11. Final verification
Do not declare success until the target state is verified.

Confirm:
- live Talos version equals approved `to_version` on every node
- repo pin equals approved `to_version`
- etcd is healthy
- all nodes are Ready
- Cilium and core cluster services are healthy
- storage health is normal
- any coupled Kubernetes or Cilium steps from the plan are complete

Capture final evidence in the run record.

## Output
Return a concise execution summary with:
- approved plan path
- versions executed
- repo changes made
- rollout sequence used
- final health status
- any incidents or remaining risks
- path to the execution record

## Hard Rules
- Never execute without an approved plan artifact that matches the planning skill’s output contract.
- Never execute a plan whose frontmatter approval fields are missing or still set to `draft`.
- Never skip the “state still matches plan” check.
- Never parallelize node upgrades.
- Never use VIP-based shortcuts where direct node endpoints are required for safety.
- Never continue past a defined stop condition.
- Never hide drift, failed checks, or partial rollout state in the final output.
