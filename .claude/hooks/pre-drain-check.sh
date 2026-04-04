#!/bin/bash
# Block kubectl drain if DRBD resources are degraded or satellites are offline.
# Prevents the DRBD D-state upgrade deadlock documented in talos-operations.md.
INPUT=$(cat)
COMMAND=$(jq -r '.tool_input.command // empty' <<< "$INPUT" 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

# Only intercept kubectl drain commands
if [[ "$COMMAND" =~ kubectl[[:space:]].*drain ]]; then
  # Extract node name — BSD-compatible (no grep -oP on macOS)
  NODE=$(echo "$COMMAND" | sed -n 's/.*drain[[:space:]]\{1,\}\([^[:space:]-][^[:space:]]*\).*/\1/p' | head -1)
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
