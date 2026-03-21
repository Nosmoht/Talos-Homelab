#!/usr/bin/env bash
# PreToolUse hook: guard-infra-commands.sh
# Blocks dangerous infrastructure commands that violate hard constraints.
# Returns JSON with permissionDecision on stdout.
#
# Receives JSON on stdin with the tool input. For Bash tool, the command
# is in .tool_input.command

# Read the JSON input from stdin
INPUT="$(cat 2>/dev/null || echo '{}')"

# Extract the command from the Bash tool input
COMMAND="$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo '')"

# Helper: block with reason
block() {
  local reason="$1"
  cat <<ENDJSON
{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"$reason"}}
ENDJSON
  exit 0
}

# Helper: allow
allow() {
  cat <<'ENDJSON'
{"hookSpecificOutput":{"permissionDecision":"allow"}}
ENDJSON
  exit 0
}

# If no command found, allow (not a Bash tool call we care about)
if [ -z "$COMMAND" ]; then
  allow
fi

# --- Hard constraint: NEVER use SecureBoot installer ---
if echo "$COMMAND" | grep -qi 'secureboot'; then
  block "SecureBoot causes boot loops on this cluster. Use metal-installer (not metal-installer-secureboot)."
fi

# --- Hard constraint: NEVER use debugfs=off ---
if echo "$COMMAND" | grep -q 'debugfs=off'; then
  block "debugfs=off causes failed to create root filesystem boot loop."
fi

# --- Hard constraint: NEVER kubectl apply ArgoCD-managed resources ---
if echo "$COMMAND" | grep -qE 'kubectl\s+apply'; then
  # Allow dry-run
  if echo "$COMMAND" | grep -q '\-\-dry-run'; then
    allow
  fi
  # Allow bootstrap directory
  if echo "$COMMAND" | grep -q 'kubernetes/bootstrap/'; then
    allow
  fi
  # Block kubectl apply in ArgoCD-managed namespaces
  MANAGED_NS="argocd|monitoring|kube-system|piraeus-datastore|cert-manager|dex|forgejo|redis-operator|local-path-provisioner"
  if echo "$COMMAND" | grep -qE "\-n\s+($MANAGED_NS)"; then
    block "Do not kubectl apply to ArgoCD-managed namespace. Commit to git and let ArgoCD sync."
  fi
  # Block kubectl apply -k / -f on overlay paths (these are ArgoCD-managed)
  if echo "$COMMAND" | grep -qE 'kubernetes/overlays/'; then
    block "Do not kubectl apply ArgoCD-managed overlays. Commit to git and let ArgoCD sync."
  fi
  # Catch-all: any remaining kubectl apply is suspicious
  block "kubectl apply detected outside bootstrap/dry-run path. Commit to git and let ArgoCD sync, or use --dry-run for validation."
fi

# --- Hard constraint: talosctl apply-config / upgrade must use explicit -e endpoint ---
if echo "$COMMAND" | grep -qE 'talosctl\s+(apply-config|upgrade|upgrade-k8s)\b'; then
  # Must have explicit -e <ip> (not VIP 192.168.2.60)
  if ! echo "$COMMAND" | grep -qE '\s(-e|--endpoints)\s+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
    block "talosctl apply-config/upgrade/upgrade-k8s requires explicit -e <node-ip> endpoint. VIP may be down during operations."
  fi
  # Block if using VIP as endpoint
  if echo "$COMMAND" | grep -qE '\s(-e|--endpoints)\s+192\.168\.2\.60\b'; then
    block "Do not use VIP (192.168.2.60) as endpoint for apply-config/upgrade. Use the nodes direct IP."
  fi
fi

# --- Hard constraint: talosctl --insecure only for maintenance-mode commands ---
if echo "$COMMAND" | grep -qE 'talosctl\b.*--insecure'; then
  if ! echo "$COMMAND" | grep -qE 'talosctl\b.*(version|get\s+(disks|systemdisk|discoveredvolumes)|apply-config)'; then
    block "--insecure only supports maintenance-mode commands: version, get disks, apply-config."
  fi
fi

# --- Safety gate: kubectl delete on dangerous resource types ---
if echo "$COMMAND" | grep -qE 'kubectl\s+delete\s+(namespace|ns|statefulset|sts|pvc|persistentvolumeclaim|crd|customresourcedefinition)\b'; then
  block "Deleting namespaces, statefulsets, PVCs, or CRDs requires manual execution. Run this command directly in your terminal."
fi

# --- Safety gate: talosctl reset ---
if echo "$COMMAND" | grep -qE 'talosctl\s+reset\b'; then
  block "talosctl reset is destructive. Run this command directly in your terminal."
fi

# --- Safety gate: rm -rf ---
if echo "$COMMAND" | grep -qE 'rm\s+-rf\b'; then
  block "rm -rf is too destructive for automated use. Run this command directly in your terminal."
fi

# All checks passed
allow
