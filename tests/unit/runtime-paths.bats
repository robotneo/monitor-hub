#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
  source "${REPO_ROOT}/lib/core/runtime-paths.sh"
}

@test "purge removes only an explicitly named child path" {
  local managed_root="${BATS_TEST_TMPDIR}/managed"
  local target="${managed_root}/demo"
  mkdir -p "${target}"
  printf 'data\n' > "${target}/payload"
  export MH_ASSUME_YES=1

  mh_purge_managed_path "${target}" "${managed_root}"

  [ ! -e "${target}" ]
  [ -d "${managed_root}" ]
}

@test "purge rejects the managed root itself" {
  local managed_root="${BATS_TEST_TMPDIR}/managed"
  mkdir -p "${managed_root}"
  export MH_ASSUME_YES=1

  run mh_purge_managed_path "${managed_root}" "${managed_root}"

  [ "$status" -ne 0 ]
  [ -d "${managed_root}" ]
}

@test "purge rejects path traversal and paths outside the managed root" {
  local managed_root="${BATS_TEST_TMPDIR}/managed"
  local unrelated="${BATS_TEST_TMPDIR}/unrelated"
  mkdir -p "${managed_root}" "${unrelated}"
  export MH_ASSUME_YES=1

  run mh_purge_managed_path "${managed_root}/../unrelated" "${managed_root}"

  [ "$status" -ne 0 ]
  [ -d "${unrelated}" ]
}

@test "purge requires confirmation unless yes is explicit" {
  local managed_root="${BATS_TEST_TMPDIR}/managed"
  local target="${managed_root}/demo"
  mkdir -p "${target}"
  export MH_ASSUME_YES=0

  run mh_purge_managed_path "${target}" "${managed_root}"

  [ "$status" -ne 0 ]
  [[ "$output" == *"--yes"* ]]
  [ -d "${target}" ]
}

@test "ownership helper uses requested uid gid and mode" {
  local fake_chown="${BATS_TEST_TMPDIR}/chown"
  local fake_chmod="${BATS_TEST_TMPDIR}/chmod"
  export MH_OWNERSHIP_LOG="${BATS_TEST_TMPDIR}/ownership.log"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "chown %s\n" "$*" >> "${MH_OWNERSHIP_LOG}"' > "${fake_chown}"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "chmod %s\n" "$*" >> "${MH_OWNERSHIP_LOG}"' > "${fake_chmod}"
  chmod +x "${fake_chown}" "${fake_chmod}"
  export MH_CHOWN_BIN="${fake_chown}" MH_CHMOD_BIN="${fake_chmod}" MH_FORCE_OWNERSHIP=1

  mh_ensure_service_directory "${BATS_TEST_TMPDIR}/data" 472 472 0750

  run grep -F "chown 472:472 ${BATS_TEST_TMPDIR}/data" "${MH_OWNERSHIP_LOG}"
  [ "$status" -eq 0 ]
  run grep -F "chmod 0750 ${BATS_TEST_TMPDIR}/data" "${MH_OWNERSHIP_LOG}"
  [ "$status" -eq 0 ]
}
