#!/bin/sh
set -eu

# Single point-of-truth Trivy wrapper used by Makefile and .pre-commit-config.yaml
# so local and CI share identical skip-files + severity gates.
# Per-finding exceptions live in .trivyignore.yaml (auto-discovered by trivy).

work_dir=${WORK_DIR:-.work}
report_file="$work_dir/trivy-report.txt"
severity=${TRIVY_SEVERITY:-HIGH,CRITICAL}

skip_files="kubernetes/bootstrap/cilium/cilium.yaml,kubernetes/overlays/homelab/infrastructure/piraeus-operator/resources/storage-pool-autovg.yaml"

if ! command -v trivy >/dev/null 2>&1; then
  cat >&2 <<EOF
error: trivy not found in PATH

Install via:
  macOS:   brew install aquasecurity/trivy/trivy
  Linux:   see https://aquasecurity.github.io/trivy/latest/getting-started/installation/

Or bypass this hook once with:
  SKIP=trivy-config git commit ...
EOF
  exit 1
fi

mkdir -p "$work_dir"

echo "trivy config scan (severity: $severity)"
trivy config \
  --severity "$severity" \
  --exit-code 1 \
  --skip-files "$skip_files" \
  --format table \
  --output "$report_file" \
  . || status=$?

status=${status:-0}
cat "$report_file"

if [ "$status" -ne 0 ]; then
  echo "trivy: HIGH/CRITICAL findings present" >&2
  exit 1
fi

echo "trivy: no HIGH/CRITICAL findings"
