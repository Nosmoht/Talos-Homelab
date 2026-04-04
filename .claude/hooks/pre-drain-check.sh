#!/bin/bash
# Block kubectl drain if DRBD resources are degraded or satellites are offline.
# Prevents the DRBD D-state upgrade deadlock documented in talos-operations.md.
INPUT=$(cat)
COMMAND=$(jq -r '.tool_input.command // empty' <<< "$INPUT" 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only intercept kubectl drain subcommand (must be followed by a space and argument)
if [[ "$COMMAND" =~ kubectl[[:space:]]+drain[[:space:]] ]]; then
  # Extract node name — skip flag tokens (starting with -), take first non-flag token after drain
  # BSD-compatible: uses tr and grep -v (no grep -oP on macOS)
  NODE=$(echo "$COMMAND" | sed 's/.*drain//' | tr ' ' '\n' | grep -v '^-' | grep -v '^$' | head -1)
  [ -z "$NODE" ] && exit 0

  # Check for degraded DRBD resources cluster-wide
  DEGRADED=$(kubectl linstor resource list 2>/dev/null | grep -c "Degraded\|SyncTarget\|Inconsistent" || true)
  if [ "$DEGRADED" -gt 0 ]; then
    echo "DRBD safety check FAILED: $DEGRADED degraded resource(s) detected. Run '/linstor-storage-triage' for details." >&2
    exit 2
  fi

  # Check for OFFLINE satellites
  OFFLINE=$(kubectl linstor node list 2>/dev/null | grep -c "OFFLINE\|UNKNOWN" || true)
  if [ "$OFFLINE" -gt 0 ]; then
    echo "DRBD safety check FAILED: $OFFLINE satellite(s) OFFLINE/UNKNOWN. Run '/linstor-storage-triage' for details." >&2
    exit 2
  fi
fi
exit 0
