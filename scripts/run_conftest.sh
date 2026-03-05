#!/bin/sh
set -eu

work_dir=${WORK_DIR:-.work}
policy_dir=${POLICY_DIR:-policies/conftest}
rendered_list=${1:-"$work_dir/kustomize-rendered-files.txt"}
apps_list=${2:-"$work_dir/argocd-applications.txt"}

if [ ! -d "$policy_dir" ]; then
  echo "error: policy directory not found: $policy_dir"
  exit 1
fi

status=0

run_conftest_for_list() {
  label=$1
  list_file=$2

  if [ ! -f "$list_file" ]; then
    echo "notice: $label list not found, skipping: $list_file"
    return
  fi

  set --
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue
    set -- "$@" "$f"
  done < "$list_file"

  if [ "$#" -eq 0 ]; then
    echo "notice: no $label files to test"
    return
  fi

  echo "conftest: testing $label files ($#)"
  if ! conftest test --policy "$policy_dir" "$@"; then
    status=1
  fi
}

run_conftest_for_list "rendered" "$rendered_list"
run_conftest_for_list "argocd application" "$apps_list"

if [ "$status" -ne 0 ]; then
  echo "conftest policy checks failed"
  exit 1
fi

echo "conftest policy checks passed"
