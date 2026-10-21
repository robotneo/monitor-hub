#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
  MH_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  export MH_STATE_DIR
  # shellcheck source=../../lib/core/state.sh
  source "${REPO_ROOT}/lib/core/state.sh"
}

@test "state is written atomically and read back" {
  local input="${BATS_TEST_TMPDIR}/input.json"
  printf '%s\n' '{"version":"1.2.0","result":"healthy"}' > "${input}"

  mh_state_write component demo "${input}"
  run mh_state_read component demo

  [ "$status" -eq 0 ]
  [ "$output" = '{"version":"1.2.0","result":"healthy"}' ]
  [ ! -e "${MH_STATE_DIR}/component/demo.json.tmp" ]
}

@test "state overwrite replaces the complete previous document" {
  local first="${BATS_TEST_TMPDIR}/first.json"
  local second="${BATS_TEST_TMPDIR}/second.json"
  printf '%s\n' '{"version":"1.1.0","obsolete":"remove-me"}' > "${first}"
  printf '%s\n' '{"version":"1.2.0"}' > "${second}"

  mh_state_write component demo "${first}"
  mh_state_write component demo "${second}"
  run mh_state_read component demo

  [ "$status" -eq 0 ]
  [ "$output" = '{"version":"1.2.0"}' ]
}

@test "missing input fails without creating a state file" {
  run mh_state_write component demo "${BATS_TEST_TMPDIR}/missing.json"

  [ "$status" -ne 0 ]
  [ ! -e "${MH_STATE_DIR}/component/demo.json" ]
}

@test "unsafe state names are rejected without writing outside state root" {
  local input="${BATS_TEST_TMPDIR}/input.json"
  printf '%s\n' '{"safe":true}' > "${input}"

  run mh_state_write component ../escape "${input}"

  [ "$status" -ne 0 ]
  [ ! -e "${MH_STATE_DIR}/escape.json" ]
  [ ! -e "${BATS_TEST_TMPDIR}/escape.json" ]
}
