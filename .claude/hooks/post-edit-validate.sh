#!/usr/bin/env bash
# PostToolUse hook: post-edit-validate.sh
# Runs synchronous kustomize validation after editing kubernetes YAML files.
# Only fires on Edit|Write matcher. Exits 0 on success or non-kubernetes files.

set -euo pipefail

# Read the JSON input from stdin
INPUT=$(cat)

# Extract the file path from the tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null)

# If no file path found, skip
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Only validate kubernetes YAML files
if ! echo "$FILE_PATH" | grep -qE 'kubernetes/.*\.ya?ml$'; then
  exit 0
fi

# Skip Helm values files (validated via helm, not kustomize directly)
BASENAME=$(basename "$FILE_PATH")
if [[ "$BASENAME" == "values.yaml" || "$BASENAME" == values-*.yaml ]]; then
  exit 0
fi

# Find the nearest parent directory with a kustomization.yaml
SEARCH_DIR=$(dirname "$FILE_PATH")
KUSTOMIZE_DIR=""

while [[ "$SEARCH_DIR" != "/" && "$SEARCH_DIR" != "." ]]; do
  if [[ -f "$SEARCH_DIR/kustomization.yaml" || -f "$SEARCH_DIR/kustomization.yml" || -f "$SEARCH_DIR/Kustomization" ]]; then
    KUSTOMIZE_DIR="$SEARCH_DIR"
    break
  fi
  SEARCH_DIR=$(dirname "$SEARCH_DIR")
done

# If no kustomization.yaml found, skip validation
if [[ -z "$KUSTOMIZE_DIR" ]]; then
  exit 0
fi

# Run kustomize build with ksops plugins enabled
# Timeout after 10 seconds to avoid blocking the session
OUTPUT=$(timeout 10 kustomize build "$KUSTOMIZE_DIR" --enable-alpha-plugins --enable-exec 2>&1) || {
  EXIT_CODE=$?
  if [[ $EXIT_CODE -eq 124 ]]; then
    echo "WARNING: kustomize build timed out after 10s for $KUSTOMIZE_DIR"
    exit 0  # Don't block on timeout
  fi
  echo "KUSTOMIZE BUILD FAILED for $KUSTOMIZE_DIR:"
  echo "$OUTPUT" | tail -20
  exit 0  # Report error but don't block (exit 0) — Claude sees the output and can fix
}

exit 0
