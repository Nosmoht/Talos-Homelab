# Freeze-Learnings — Talos-Homelab Primitives

Append-only backlog for primitive ideas and friction points observed during the `kube-agent-harness` freeze phase. Entries here are not acted on during freeze — they feed the switch-project backlog.

## Context

Talos-Homelab `.claude/skills/**`, `rules/**`, `agents/**` are frozen until the harness is declared "done" (hard stop 2026-07-13). New primitive work happens in `github.com/devobagmbh/kube-agent-harness` during the freeze. See `Plans/swirling-strolling-alpaca.md` for the full freeze rule and carve-out.

## How to log an entry

Append below. Do not edit earlier entries. Format:

```
### <YYYY-MM-DD> — <short title>

**Context:** what were you doing / what broke / what felt missing
**Proposal:** what primitive (skill/rule/agent) would help, or what existing one needs what change
**Target:** where the proposal should land (harness Core / harness provider / Homelab-only keeping or creating)
**Links:** PR, issue, incident, commit refs
```

Alternative: open a GitHub issue with label `freeze-learning` — preferred if issue flow is already active.

## Entries

<!-- New entries below this marker. Newest at the bottom. -->

### 2026-04-15 — Emergency exception: two rule files edited outside carve-out

**Context:** During MinIO root-credential rotation incident follow-up, a `rollout restart deploy linstor-controller` issued as a routine diagnostic triggered a cert-manager rotation with ECDSA/RSA algorithm mismatch and flipped all six LINSTOR satellites OFFLINE, causing a full storage control-plane outage. Parallel research on MinIO revealed both `minio/operator` and `minio/minio` upstream repos archived in Q1 2026 with the `AdminJob` CRD reconciler never shipping in any tagged release. Leaving both findings only in per-user Claude memory would guarantee repeat incidents in future sessions (other tools, other operators) since the guardrails would not surface when someone edits MinIO or LINSTOR manifests.

**Decision:** User (sole maintainer) granted a narrow emergency exception to the primitives freeze for this one migration. The freeze otherwise remains in effect until the 2026-07-13 hard-stop.

**Proposal:** N/A — work already completed. Audit trail:
- `docs(linstor): capture controller-restart SSL failure mode in guardrails` (commit `c93b08f`) — extends `.claude/rules/linstor-storage-guardrails.md` § Known Failure Modes and § Safety Constraints.
- `docs(minio): add end-of-life exit posture rule` (commit `532f6d5`) — creates `.claude/rules/minio-exit.md` with `paths:` frontmatter and adds row to `AGENTS.md` § Domain Rules table.

**Target:** Already landed in `.claude/rules/`. No follow-up action for the switch-project.

**Links:** `Plans/snappy-growing-boole.md`, commits `c93b08f` and `532f6d5`, session 2026-04-15. Memory `project_homelab_primitives_frozen.md` updated with matching exception record.
