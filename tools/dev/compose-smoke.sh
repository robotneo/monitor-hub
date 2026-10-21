#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
if ! command -v docker >/dev/null 2>&1; then
  printf 'SKIP: Docker CLI is unavailable; Compose smoke test was not run.\n'
  exit 0
fi
if ! docker compose version >/dev/null 2>&1; then
  printf 'SKIP: Docker Compose plugin is unavailable; Compose smoke test was not run.\n'
  exit 0
fi

if (( $# > 0 )); then stacks=("$@")
else stacks=(victoriametrics-monitoring nightingale-monitoring hybrid-monitoring)
fi

smoke_root="$(mktemp -d "${TMPDIR:-/tmp}/monitor-hub-smoke.XXXXXX")"
cleanup() { rm -rf "${smoke_root}"; }
trap cleanup EXIT

printf 'SKIP: VMware integration is disabled because no external vCenter credentials are supplied.\n'
for stack in "${stacks[@]}"; do
  export MH_CONFIG_DIR="${smoke_root}/config/${stack}"
  export MH_DATA_DIR="${smoke_root}/data/${stack}"
  export MH_BACKUP_DIR="${smoke_root}/backups"
  printf 'smoke: validating %s\n' "${stack}"
  "${repo_root}/bin/monitorctl" stack "${stack}" validate --mode compose --profile single-node
  printf 'smoke: starting %s\n' "${stack}"
  "${repo_root}/bin/monitorctl" stack "${stack}" install --mode compose --profile single-node
  "${repo_root}/bin/monitorctl" stack "${stack}" doctor --mode compose --profile single-node
  "${repo_root}/bin/monitorctl" stack "${stack}" uninstall --mode compose --profile single-node --yes
  [[ -d "${MH_DATA_DIR}/stacks/${stack}" ]] || { printf 'data preservation check failed: %s\n' "${stack}" >&2; exit 1; }
done
