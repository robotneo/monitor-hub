#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
  MONITORCTL="${REPO_ROOT}/bin/monitorctl"
  MH_COMPONENTS_DIR="${BATS_TEST_TMPDIR}/components"
  MH_STACKS_DIR="${BATS_TEST_TMPDIR}/stacks"
  MH_TEST_LOG="${BATS_TEST_TMPDIR}/hook.log"
  MH_TEST_DATA="${BATS_TEST_TMPDIR}/data"
  mkdir -p "${MH_COMPONENTS_DIR}/demo/hooks" "${MH_STACKS_DIR}/demo-stack/hooks" "${MH_TEST_DATA}"
  printf 'keep\n' > "${MH_TEST_DATA}/payload"
  printf '%s\n' \
    'name: demo' \
    'modes:' \
    '  - native' \
    '  - compose' \
    > "${MH_COMPONENTS_DIR}/demo/component.yaml"
  printf '%s\n' \
    'name: demo-stack' \
    'profiles:' \
    '  single-node:' \
    '    description: test' \
    'modes:' \
    '  - compose' \
    > "${MH_STACKS_DIR}/demo-stack/stack.yaml"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'component_lifecycle() {' \
    '  if [[ "${MH_DRY_RUN}" == "1" ]]; then printf "dry-run %s %s\\n" "$1" "$2"; return 0; fi' \
    '  printf "%s %s %s yes=%s purge=%s\\n" "$1" "$2" "$3" "${MH_ASSUME_YES}" "${MH_PURGE_DATA}" >> "${MH_TEST_LOG}"' \
    '  if [[ "$1" == "uninstall" && "${MH_PURGE_DATA}" == "1" ]]; then rm -f "${MH_TEST_DATA}/payload"; fi' \
    '}' \
    > "${MH_COMPONENTS_DIR}/demo/hooks/lifecycle.sh"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'stack_lifecycle() { printf "%s %s %s\\n" "$1" "$2" "$3" >> "${MH_TEST_LOG}"; }' \
    > "${MH_STACKS_DIR}/demo-stack/hooks/lifecycle.sh"
  export MH_COMPONENTS_DIR MH_STACKS_DIR MH_TEST_LOG MH_TEST_DATA
}

@test "help documents the lifecycle interface" {
  run "${MONITORCTL}" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"monitorctl <component|stack> <name> <action>"* ]]
  [[ "$output" == *"--purge-data"* ]]
}

@test "unknown actions are rejected" {
  run "${MONITORCTL}" component demo explode --mode native

  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown action"* ]]
}

@test "unknown deployment modes are rejected" {
  run "${MONITORCTL}" component demo status --mode magic

  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown mode"* ]]
}

@test "stack operations require a profile" {
  run "${MONITORCTL}" stack demo-stack status --mode compose

  [ "$status" -ne 0 ]
  [[ "$output" == *"--profile is required"* ]]
}

@test "relative path traversal names are rejected" {
  run "${MONITORCTL}" component ../demo status --mode native

  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid name"* ]]
}

@test "absolute path names are rejected" {
  run "${MONITORCTL}" component /tmp/demo status --mode native

  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid name"* ]]
}

@test "dry-run reaches the hook without persistent writes" {
  run "${MONITORCTL}" component demo install --mode native --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run install native"* ]]
  [ ! -e "${MH_TEST_LOG}" ]
}

@test "yes does not imply purge-data" {
  run "${MONITORCTL}" component demo uninstall --mode native --yes

  [ "$status" -eq 0 ]
  [ -f "${MH_TEST_DATA}/payload" ]
  run grep -F 'yes=1 purge=0' "${MH_TEST_LOG}"
  [ "$status" -eq 0 ]
}

@test "uninstall preserves data unless purge-data is explicit" {
  run "${MONITORCTL}" component demo uninstall --mode native
  [ "$status" -eq 0 ]
  [ -f "${MH_TEST_DATA}/payload" ]

  run "${MONITORCTL}" component demo uninstall --mode native --purge-data --yes
  [ "$status" -eq 0 ]
  [ ! -e "${MH_TEST_DATA}/payload" ]
}

@test "undefined stack profiles are rejected" {
  run "${MONITORCTL}" stack demo-stack status --mode compose --profile missing

  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown profile"* ]]
}

@test "every shipped component metadata file dispatches compose mode" {
  local component metadata
  source "${REPO_ROOT}/lib/core/dispatch.sh"

  for metadata in "${REPO_ROOT}"/components/*/component.yaml; do
    component="$(basename "$(dirname "${metadata}")")"
    run mh_metadata_supports_mode "${metadata}" compose
    [ "$status" -eq 0 ]
  done
}

@test "every shipped stack metadata file dispatches compose mode" {
  local metadata
  source "${REPO_ROOT}/lib/core/dispatch.sh"

  for metadata in "${REPO_ROOT}"/stacks/*/stack.yaml; do
    run mh_metadata_supports_mode "${metadata}" compose
    [ "$status" -eq 0 ]
  done
}
