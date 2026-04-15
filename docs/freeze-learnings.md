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
