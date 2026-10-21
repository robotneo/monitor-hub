#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
  # shellcheck source=../../lib/core/log.sh
  source "${REPO_ROOT}/lib/core/log.sh"
}

@test "logger redacts every registered secret" {
  mh_register_secret "vcenter-password"
  mh_register_secret "webhook-token"

  run mh_log info "password=vcenter-password token=webhook-token"

  [ "$status" -eq 0 ]
  [[ "$output" == *"password=[REDACTED]"* ]]
  [[ "$output" == *"token=[REDACTED]"* ]]
  [[ "$output" != *"vcenter-password"* ]]
  [[ "$output" != *"webhook-token"* ]]
}

@test "logger suppresses messages below the configured level" {
  MH_LOG_LEVEL=warn

  run mh_log info "hidden"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "logger rejects unknown levels" {
  run mh_log noisy "not valid"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown log level"* ]]
}
