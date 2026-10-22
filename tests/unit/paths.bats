#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
  # shellcheck source=../../lib/core/paths.sh
  source "${REPO_ROOT}/lib/core/paths.sh"
}

@test "runtime paths use the standard host filesystem contract" {
  MH_ROOT_DIR=/

  mh_init_paths

  [ "${MH_CONFIG_DIR}" = "/etc/monitor-hub" ]
  [ "${MH_DATA_DIR}" = "/var/lib/monitor-hub" ]
  [ "${MH_STATE_DIR}" = "/var/lib/monitor-hub" ]
  [ "${MH_CACHE_DIR}" = "/var/cache/monitor-hub" ]
  [ "${MH_LOG_DIR}" = "/var/log/monitor-hub" ]
  [ "${MH_BACKUP_DIR}" = "/var/backups/monitor-hub" ]
}

@test "runtime paths preserve the same layout below a test root" {
  MH_ROOT_DIR="${BATS_TEST_TMPDIR}/root"

  mh_init_paths

  [ "${MH_CONFIG_DIR}" = "${MH_ROOT_DIR}/etc/monitor-hub" ]
  [ "${MH_DATA_DIR}" = "${MH_ROOT_DIR}/var/lib/monitor-hub" ]
  [ "${MH_STATE_DIR}" = "${MH_ROOT_DIR}/var/lib/monitor-hub" ]
  [ "${MH_CACHE_DIR}" = "${MH_ROOT_DIR}/var/cache/monitor-hub" ]
  [ "${MH_LOG_DIR}" = "${MH_ROOT_DIR}/var/log/monitor-hub" ]
  [ "${MH_BACKUP_DIR}" = "${MH_ROOT_DIR}/var/backups/monitor-hub" ]
  [ ! -e "${MH_ROOT_DIR}" ]
}

@test "explicit runtime path overrides are preserved" {
  MH_ROOT_DIR="${BATS_TEST_TMPDIR}/root"
  MH_CONFIG_DIR="${BATS_TEST_TMPDIR}/custom-config"
  MH_DATA_DIR="${BATS_TEST_TMPDIR}/custom-data"

  mh_init_paths

  [ "${MH_CONFIG_DIR}" = "${BATS_TEST_TMPDIR}/custom-config" ]
  [ "${MH_DATA_DIR}" = "${BATS_TEST_TMPDIR}/custom-data" ]
}
