#!/usr/bin/env bash
# PreToolUse hook: guard-infra-commands.sh
# Blocks dangerous infrastructure commands that violate hard constraints.
# Exit 0 = allow, Exit 2 = block (with message on stdout).
#
# Receives JSON on stdin with the tool input. For Bash tool, the command
# is in .tool_input.command

# Read the JSON input from stdin
INPUT="$(cat 2>/dev/null || echo '{}')"

# Extract the command from the Bash tool input
COMMAND="$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo '')"

# If no command found, allow (not a Bash tool call we care about)
if [ -z "$COMMAND" ]; then
  exit 0
fi

# --- Hard constraint: NEVER use SecureBoot installer ---
if echo "$COMMAND" | grep -qi 'secureboot'; then
  echo "BLOCKED: SecureBoot causes boot loops on this cluster. Use metal-installer (not metal-installer-secureboot)."
  exit 2
fi

# --- Hard constraint: NEVER use debugfs=off ---
if echo "$COMMAND" | grep -q 'debugfs=off'; then
  echo "BLOCKED: debugfs=off causes 'failed to create root filesystem' boot loop."
  exit 2
fi

# --- Hard constraint: NEVER kubectl apply ArgoCD-managed resources ---
# Allow kubectl apply only for dry-run, bootstrap paths, and non-managed contexts
if echo "$COMMAND" | grep -qE 'kubectl\s+apply'; then
  # Allow dry-run
  if echo "$COMMAND" | grep -q '\-\-dry-run'; then
    exit 0
  fi
  # Allow bootstrap directory
  if echo "$COMMAND" | grep -q 'kubernetes/bootstrap/'; then
    exit 0
  fi
  # Block kubectl apply in ArgoCD-managed namespaces
  MANAGED_NS="argocd|monitoring|kube-system|piraeus-datastore|cert-manager|dex|forgejo|redis-operator|local-path-provisioner"
  if echo "$COMMAND" | grep -qE "\-n\s+($MANAGED_NS)"; then
    echo "BLOCKED: Do not kubectl apply to ArgoCD-managed namespace. Commit to git and let ArgoCD sync."
    exit 2
  fi
  # Block kubectl apply -k / -f on overlay paths (these are ArgoCD-managed)
  if echo "$COMMAND" | grep -qE 'kubernetes/overlays/'; then
    echo "BLOCKED: Do not kubectl apply ArgoCD-managed overlays. Commit to git and let ArgoCD sync."
    exit 2
  fi
  # Catch-all: any remaining kubectl apply is suspicious
  echo "BLOCKED: kubectl apply detected outside bootstrap/dry-run path. Commit to git and let ArgoCD sync, or use --dry-run for validation."
  exit 2
fi

# --- Hard constraint: talosctl apply-config / upgrade must use explicit -e endpoint ---
if echo "$COMMAND" | grep -qE 'talosctl\s+(apply-config|upgrade|upgrade-k8s)\b'; then
  # Must have explicit -e <ip> (not VIP 192.168.2.60)
  if ! echo "$COMMAND" | grep -qE '\s(-e|--endpoints)\s+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
    echo "BLOCKED: talosctl apply-config/upgrade/upgrade-k8s requires explicit -e <node-ip> endpoint. VIP may be down during operations."
    exit 2
  fi
  # Block if using VIP as endpoint
  if echo "$COMMAND" | grep -qE '\s(-e|--endpoints)\s+192\.168\.2\.60\b'; then
    echo "BLOCKED: Do not use VIP (192.168.2.60) as endpoint for apply-config/upgrade. Use the node's direct IP."
    exit 2
  fi
fi

# --- Hard constraint: talosctl --insecure only for maintenance-mode commands ---
if echo "$COMMAND" | grep -qE 'talosctl\b.*--insecure'; then
  # Only allow: version, get disks, apply-config
  if ! echo "$COMMAND" | grep -qE 'talosctl\b.*(version|get\s+(disks|systemdisk|discoveredvolumes)|apply-config)'; then
    echo "BLOCKED: --insecure only supports maintenance-mode commands: version, get disks, apply-config."
    exit 2
  fi
fi

# --- Safety gate: kubectl delete on dangerous resource types ---
if echo "$COMMAND" | grep -qE 'kubectl\s+delete\s+(namespace|ns|statefulset|sts|pvc|persistentvolumeclaim|crd|customresourcedefinition)\b'; then
  echo "BLOCKED: Deleting namespaces, statefulsets, PVCs, or CRDs requires manual execution. Run this command directly in your terminal."
  exit 2
fi

# --- Safety gate: talosctl reset ---
if echo "$COMMAND" | grep -qE 'talosctl\s+reset\b'; then
  echo "BLOCKED: talosctl reset is destructive. Run this command directly in your terminal."
  exit 2
fi

# --- Safety gate: rm -rf ---
if echo "$COMMAND" | grep -qE 'rm\s+-rf\b'; then
  echo "BLOCKED: rm -rf is too destructive for automated use. Run this command directly in your terminal."
  exit 2
fi

# All checks passed
exit 0
