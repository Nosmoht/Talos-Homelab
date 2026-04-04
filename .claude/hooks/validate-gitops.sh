#!/bin/bash
# Block git commit if staged kubernetes/ changes fail GitOps validation.
# Follows the same pattern as check-sops.sh (PreToolUse, exit 2 to block).
# Intentionally skips conftest + trivy (slow) — the full pipeline is in the skill and CI.
INPUT=$(cat)
COMMAND=$(jq -r '.tool_input.command // empty' <<< "$INPUT" 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only intercept git commit (NOT push — push sends already-committed work).
# No ^ anchor: handles prefixed commands like "cd /path && git commit".
if [[ "$COMMAND" =~ git[[:space:]]commit ]]; then
  cd "$CLAUDE_PROJECT_DIR" || exit 0

  # Fast-path: skip validation if no kubernetes/ files are staged
  if ! git diff --cached --name-only 2>/dev/null | grep -q '^kubernetes/'; then
    exit 0
  fi

  # Run kustomize render (the most common failure)
  if ! kubectl kustomize kubernetes/overlays/homelab > /dev/null 2>&1; then
    echo "validate-gitops FAILED: kustomize render error. Run 'kubectl kustomize kubernetes/overlays/homelab' to see details." >&2
    exit 2
  fi

  # Run kubeconform on rendered output (quick schema check)
  if command -v kubeconform &> /dev/null; then
    if ! kubectl kustomize kubernetes/overlays/homelab 2>/dev/null | kubeconform -strict -ignore-missing-schemas > /dev/null 2>&1; then
      echo "validate-gitops FAILED: kubeconform schema error. Run 'kubectl kustomize kubernetes/overlays/homelab | kubeconform -strict -ignore-missing-schemas' for details." >&2
      exit 2
    fi
  fi
fi
exit 0
