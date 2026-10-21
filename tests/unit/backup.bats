#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
  MH_BACKUP_DIR="${BATS_TEST_TMPDIR}/backups"
  export MH_BACKUP_DIR
  # shellcheck source=../../lib/core/backup.sh
  source "${REPO_ROOT}/lib/core/backup.sh"
}

@test "backup contains a source manifest and SHA256 checksums" {
  local config="${BATS_TEST_TMPDIR}/config.yml"
  local data_dir="${BATS_TEST_TMPDIR}/data"
  mkdir -p "${data_dir}"
  printf 'config\n' > "${config}"
  printf 'metrics\n' > "${data_dir}/metrics.db"

  mh_backup_create component demo "${config}" "${data_dir}"

  [ -f "${MH_BACKUP_PATH}/manifest.tsv" ]
  [ -f "${MH_BACKUP_PATH}/checksums.sha256" ]
  run grep -F "${config}" "${MH_BACKUP_PATH}/manifest.tsv"
  [ "$status" -eq 0 ]
  run grep -E '^[0-9a-f]{64}  files/' "${MH_BACKUP_PATH}/checksums.sha256"
  [ "$status" -eq 0 ]
}

@test "backup restore replaces modified source files" {
  local config="${BATS_TEST_TMPDIR}/config.yml"
  printf 'old config\n' > "${config}"
  mh_backup_create component demo "${config}"
  printf 'new config\n' > "${config}"

  mh_backup_restore "${MH_BACKUP_PATH}"

  [ "$(cat "${config}")" = "old config" ]
}
