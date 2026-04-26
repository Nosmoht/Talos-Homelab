---
name: kernel-param-auditor
description: Audit kernel sysctl parameters across nodes via Talos MCP. Detect drift from per-role baselines (cp/worker/storage/gpu), classify CRITICAL/WARNING by parameter+role. Read-only — never auto-applies. Emits per-node JSON conforming to docs/primitive-contract.md.
disable-model-invocation: true
argument-hint: "[--node <name>] [--role <cp|worker|storage|gpu>] [--json] [--save-baseline]"
allowed-tools:
  - mcp__talos__talos_read_file
  - mcp__kubernetes-mcp-server__resources_list
  - Bash
  - Read
  - Write
model: inherit
---

# Kernel Parameter Auditor

Read sysctl values per node from `/proc/sys/<key>` via Talos MCP, classify drift against the per-role baseline table in `references/role-baselines.md`, emit JSON conforming to `docs/primitive-contract.md`.

## Environment Setup

Read `.claude/environment.yaml` for kubeconfig path. If missing, stop: "Copy `.claude/environment.example.yaml` to `.claude/environment.yaml` and fill in your cluster details."

```bash
KUBECONFIG=$(yq '.kubeconfig' .claude/environment.yaml)
```

## Reference Files

Read before acting:
- `references/role-baselines.md` — parameter list, per-role expected values, severity rules, role-detection priority
- `docs/primitive-contract.md` — output schema, fail-closed semantics, schema version
- `.claude/rules/talos-mcp-first.md` — Talos MCP usage policy
- `.claude/rules/kubernetes-mcp-first.md` — MCP-first failure taxonomy (case a/b/c)

## Inputs

`$ARGUMENTS` (optional):
- `--node <name>` — limit audit to one node; default: all nodes via `resources_list`
- `--role <cp|worker|storage|gpu>` — override role detection (debug aid; do not use in routine runs)
- `--json` — emit JSON only, no human-readable summary; default: emit both
- `--save-baseline` — persist current snapshot under `tests/baselines/kernel-param-auditor/<node>-<YYYY-MM-DD>.json`

## Scope Guard

Read-only diagnostic. Never writes to `/proc/sys/` or proposes a write. For drift remediation, the operator updates Talos `MachineConfig` (`.machine.sysctls`) and re-applies via the Talos lifecycle — outside this skill's remit. Per-tenant `pod.spec.securityContext.sysctls` is not in scope: this skill audits node-scope parameters only.

## Workflow

### 1. Resolve schema version (fail-closed)

```bash
CONTRACT_PATH="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo /nonexistent)}/docs/primitive-contract.md"
SCHEMA_VERSION=$(yq e '.schema_version' "$CONTRACT_PATH" 2>/dev/null) \
  || { jq -n --arg p "kernel-param-auditor" '{primitive:$p,verdict:"PRECONDITION_NOT_MET",reason:"contract not readable",timestamp:now|todate}'; exit 0; }
[ -z "$SCHEMA_VERSION" ] && SCHEMA_VERSION="unknown"
```

### 2. Load baseline table

Read `references/role-baselines.md`. Parse the **Baseline Table** rows into a map keyed by parameter path (`<param> -> {cp, worker, storage, gpu, category}`). Parse the **Severity Table** rows into a map keyed by parameter path (`<param> -> {default_severity, critical_roles}`).

If the file is missing or no rows parse, emit `PRECONDITION_NOT_MET` with reason `"role-baselines.md not readable or empty"` and stop.

### 3. Discover target nodes

If `--node <name>` is given: resolve its IP via `resources_list` and limit to that one node.

Else, list all nodes:
```
resources_list(apiVersion="v1", kind="Node")
# Fallback: KUBECONFIG=$KUBECONFIG kubectl get nodes -o json
```

Extract from each item:
- `metadata.name` → node name
- `status.addresses[?type=="InternalIP"].address` → node IP
- `metadata.labels` → label map (used for role detection)

If `resources_list` returns empty (case b — valid zero result), emit `PRECONDITION_NOT_MET` describing "no nodes discovered" and stop. Do NOT retry against kubectl on empty.

If `resources_list` errors or times out (case a), retry once, then fall back to `kubectl get nodes -o json` and log the fallback in the report.

### 4. Determine role per node

For each node, apply role-detection priority from `references/role-baselines.md` §Roles:

1. Label `node-role.kubernetes.io/control-plane` present (value `""` or `"true"`) → `cp`
2. Else if label `feature.node.kubernetes.io/storage-nvme.present == "true"` → `storage`
3. Else if node name contains `gpu` OR label `node.kubernetes.io/gpu` present → `gpu`
4. Else → `worker` (and append finding `"role inference fell back to worker for node <name>"`)

If `--role` is given, override the detected role for ALL targeted nodes and append finding `"role override active: --role=<R>"`.

### 5. Read sysctl values per node

For each (node IP, parameter) in the baseline table where the role's column is not empty:

```
talos_read_file(path="/proc/sys/<param>", nodes=["<node-ip>"])
```

Parse the returned content:
- Trim leading/trailing whitespace and trailing newline.
- For tuple parameters (e.g. `tcp_rmem`, `tcp_wmem`), collapse internal whitespace to single spaces.
- Treat the result as a string (kernel exposes integers as text in `/proc/sys/`).

If the read fails (path absent on this kernel build, MCP error): record `actual: null`, status `PRECONDITION_NOT_MET` for that parameter, continue with the next parameter.

If ALL parameter reads fail for a node: mark that node `verdict: PRECONDITION_NOT_MET` in `results[]` and continue with other nodes.

### 6. Classify drift per parameter

For each (node, parameter) pair:

- If `expected == "*"` → status `INFO` (probed for evidence; no verdict effect).
- Else if `actual == expected` (after trim/whitespace-collapse) → status `OK`.
- Else if the node's role is in the parameter's `critical_roles` list → status `CRITICAL`, append finding `"<param>: expected <expected>, actual <actual> (role=<role>, severity=CRITICAL)"`.
- Else → status `WARNING`, append finding `"<param>: expected <expected>, actual <actual> (role=<role>, severity=WARNING)"`.

### 7. Per-node verdict

Apply precedence `CRITICAL > WARNING > HEALTHY`. `OK` and `INFO` collapse to `HEALTHY`. `PRECONDITION_NOT_MET` is per-parameter only and does not raise the node verdict by itself; the node-level `PRECONDITION_NOT_MET` is set only when ALL parameter reads fail for that node.

### 8. Emit JSON

Build canonical output. Note the `role` field per result is a primitive-specific extension to the §B3 schema:

```json
{
  "primitive": "kernel-param-auditor",
  "version": "<SCHEMA_VERSION from §1>",
  "timestamp": "<ISO-8601 UTC>",
  "verdict": "<aggregate: worst per-node>",
  "shape": "per_node",
  "preconditions": {
    "required": ["talos_mcp", "proc_sys", "role-baselines.md"],
    "met": true
  },
  "results": [
    {
      "node": "<name>",
      "role": "cp|worker|storage|gpu",
      "verdict": "HEALTHY|WARNING|CRITICAL|PRECONDITION_NOT_MET",
      "metrics": {
        "<param>": {
          "expected": "<value-or-*>",
          "actual": "<value-or-null>",
          "status": "OK|WARNING|CRITICAL|INFO|PRECONDITION_NOT_MET"
        }
      },
      "findings": ["<string>", ...]
    }
  ],
  "summary": {
    "healthy": N,
    "warning": N,
    "critical": N
  }
}
```

Aggregate-verdict precedence: `CRITICAL > WARNING > HEALTHY > PRECONDITION_NOT_MET`.

### 9. Optional baseline persist

If `--save-baseline` is given: for each node, write a JSON file at `tests/baselines/kernel-param-auditor/<node>-<YYYY-MM-DD>.json` containing only the `metrics` block for that node plus its `role`. No verdict, no findings — just the raw read snapshot. Useful when promoting a freshly-tuned cluster's values into the baseline table by hand.

## Output

If `--json` only: emit the JSON to stdout. Done.

Else: emit the JSON, then a human-readable summary table:

```
| Node       | Role    | Verdict  | Findings (drift count) |
|------------|---------|----------|------------------------|
| node-01    | cp      | HEALTHY  | 0                      |
| node-04    | worker  | WARNING  | 2 (vm.dirty_ratio, ...)|
| node-pi-01 | worker  | CRITICAL | 1 (ip_forward=0)       |
```

Order: CRITICAL first, then WARNING, then HEALTHY, then PRECONDITION_NOT_MET.

## Hard Rules

- Read-only: never write to `/proc/sys/`, never propose a write through this skill, never call `talos_apply_config` or any mutating MCP tool.
- Talos MCP `talos_read_file` for all `/proc/sys/` access — never `talosctl read` CLI from this skill.
- Aggregate `verdict` is the worst per-node verdict.
- `role` field per result is a primitive-specific extension to schema §B3; downstream consumers (Phase 5 composite #113) must tolerate its presence.
- Never fabricate values; if a read fails for a parameter, record `actual: null` with status `PRECONDITION_NOT_MET` and continue.
- Bash strict-mode (`set -euo pipefail`) compatible — see §1 yq lookup pattern.
- On Kubernetes MCP tool failure (case a): retry once, then run the `# Fallback: kubectl ...` command. Empty result (case b) is reported as-is, no fallback.
