#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
  if [[ -z "${MH_HISTORY_BACKUP:-}" || -z "${MH_HISTORY_REWRITE:-}" ]]; then
    skip 'set MH_HISTORY_BACKUP and MH_HISTORY_REWRITE to audit Git history'
  fi
  HISTORY_BACKUP="${MH_HISTORY_BACKUP}"
  HISTORY_REWRITE="${MH_HISTORY_REWRITE}"
}

@test "rewritten refs no longer contain the legacy VMware config path" {
  run git -C "${HISTORY_REWRITE}" log --all --format='%H' -- vmware/config.yml

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "reachable rewritten commits contain no assigned vSphere password" {
  run bash -c '
    set -euo pipefail
    repository="$1"
    field="vsphere_""password"
    assigned_pattern="${field}:[[:space:]]+[^$<[:space:]][^[:space:]]*"
    while IFS= read -r commit; do
      if git -C "${repository}" grep -I -q -E \
        "${assigned_pattern}" \
        "${commit}" -- .; then
        exit 1
      fi
    done < <(git -C "${repository}" rev-list --all)
  ' _ "${HISTORY_REWRITE}"

  [ "$status" -eq 0 ]
}

@test "rewritten main retains the sanitized VMware exporter component" {
  run git -C "${HISTORY_REWRITE}" cat-file -e \
    'refs/heads/main:components/vmware-exporter/config/config.yml'

  [ "$status" -eq 0 ]
}

@test "backup mirror retains readable original refs" {
  run git -C "${HISTORY_BACKUP}" show-ref --verify --quiet refs/heads/main

  [ "$status" -eq 0 ]
  run git -C "${HISTORY_BACKUP}" fsck --no-dangling
  [ "$status" -eq 0 ]
}
