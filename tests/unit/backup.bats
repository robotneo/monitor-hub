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

@test "backups created in the same second use distinct immutable directories" {
  local config="${BATS_TEST_TMPDIR}/config.yml"
  local first_backup second_backup
  date() { printf '20261022T010203Z\n'; }
  printf 'first\n' > "${config}"
  mh_backup_create component demo "${config}"
  first_backup="${MH_BACKUP_PATH}"
  printf 'second\n' > "${config}"
  mh_backup_create component demo "${config}"
  second_backup="${MH_BACKUP_PATH}"

  [ "${first_backup}" != "${second_backup}" ]
  mh_backup_restore "${first_backup}" "${config}"
  [ "$(cat "${config}")" = "first" ]
}

@test "backup restore replaces modified source files" {
  local config="${BATS_TEST_TMPDIR}/config.yml"
  printf 'old config\n' > "${config}"
  mh_backup_create component demo "${config}"
  printf 'new config\n' > "${config}"

  mh_backup_restore "${MH_BACKUP_PATH}" "${config}"

  [ "$(cat "${config}")" = "old config" ]
}

@test "restore rejects a checksum mismatch before changing destinations" {
  local config="${BATS_TEST_TMPDIR}/config.yml"
  printf 'old config\n' > "${config}"
  mh_backup_create component demo "${config}"
  printf 'tampered backup\n' > "${MH_BACKUP_PATH}/files/0-config.yml"
  printf 'current config\n' > "${config}"

  run mh_backup_restore "${MH_BACKUP_PATH}" "${config}"

  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum"* ]]
  [ "$(cat "${config}")" = "current config" ]
}

@test "restore rejects destinations outside the allowed roots" {
  local config="${BATS_TEST_TMPDIR}/config.yml"
  local unrelated="${BATS_TEST_TMPDIR}/unrelated.yml"
  printf 'old config\n' > "${config}"
  printf 'keep me\n' > "${unrelated}"
  mh_backup_create component demo "${config}"
  sed -i.bak "s#${config}#${unrelated}#" "${MH_BACKUP_PATH}/manifest.tsv"
  rm -f "${MH_BACKUP_PATH}/manifest.tsv.bak"

  run mh_backup_restore "${MH_BACKUP_PATH}" "${config}"

  [ "$status" -ne 0 ]
  [[ "$output" == *"outside allowed roots"* ]]
  [ "$(cat "${unrelated}")" = "keep me" ]
}

@test "restore rejects traversal in stored backup paths" {
  local config="${BATS_TEST_TMPDIR}/config.yml"
  printf 'old config\n' > "${config}"
  mh_backup_create component demo "${config}"
  sed -i.bak 's#files/0-config.yml#files/../manifest.tsv#' "${MH_BACKUP_PATH}/manifest.tsv"
  rm -f "${MH_BACKUP_PATH}/manifest.tsv.bak"

  run mh_backup_restore "${MH_BACKUP_PATH}" "${config}"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsafe stored path"* ]]
}

@test "restore rejects traversal in destination paths after normalization" {
  local config="${BATS_TEST_TMPDIR}/config"
  local outside="${BATS_TEST_TMPDIR}/outside"
  mkdir -p "${config}" "${outside}"
  printf 'candidate\n' > "${config}/app.yml"
  printf 'keep\n' > "${outside}/app.yml"
  mh_backup_create component demo "${config}"
  awk -F '\t' -v target="${config}/../outside" 'BEGIN { OFS="\t" }
    NR == 1 { print; next }
    { $1 = target; print }
  ' "${MH_BACKUP_PATH}/manifest.tsv" > "${MH_BACKUP_PATH}/manifest.tsv.tmp"
  mv "${MH_BACKUP_PATH}/manifest.tsv.tmp" "${MH_BACKUP_PATH}/manifest.tsv"

  run mh_backup_restore "${MH_BACKUP_PATH}" "${config}"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsafe restore destination"* ]]
  [ "$(cat "${outside}/app.yml")" = "keep" ]
}

@test "restore rejects symbolic links in backup metadata" {
  local config="${BATS_TEST_TMPDIR}/config.yml"
  printf 'candidate\n' > "${config}"
  mh_backup_create component demo "${config}"
  mv "${MH_BACKUP_PATH}/manifest.tsv" "${MH_BACKUP_PATH}/manifest.real.tsv"
  ln -s "manifest.real.tsv" "${MH_BACKUP_PATH}/manifest.tsv"
  printf 'current\n' > "${config}"

  run mh_backup_restore "${MH_BACKUP_PATH}" "${config}"

  [ "$status" -ne 0 ]
  [[ "$output" == *"symbolic link"* ]]
  [ "$(cat "${config}")" = "current" ]
}
