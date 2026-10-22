#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
  MH_TRANSACTION_ROOT="${BATS_TEST_TMPDIR}/transactions"
  TX_LOG="${BATS_TEST_TMPDIR}/stages.log"
  TX_CONFIG="${BATS_TEST_TMPDIR}/config.yml"
  TX_STATE="${BATS_TEST_TMPDIR}/state.json"
  export MH_TRANSACTION_ROOT TX_LOG TX_CONFIG TX_STATE
  # shellcheck source=../../lib/core/transaction.sh
  source "${REPO_ROOT}/lib/core/transaction.sh"
}

record_stage() {
  printf '%s\n' "$1" >> "${TX_LOG}"
}

tx_preflight() { record_stage preflight; }
tx_resolve() { record_stage resolve; }
tx_backup() {
  record_stage backup
  mh_transaction_track "${TX_CONFIG}"
  mh_transaction_track "${TX_STATE}"
}
tx_render() {
  record_stage render
  printf 'rendered\n' > "${MH_TX_DIR}/rendered-config"
}
tx_validate_ok() { record_stage validate; }
tx_validate_fail() { record_stage validate; return 1; }
tx_apply() {
  record_stage apply
  printf 'new config\n' > "${TX_CONFIG}"
  printf '{"version":"new"}\n' > "${TX_STATE}"
}
tx_health_ok() { record_stage health; }
tx_health_fail() { record_stage health; return 1; }
tx_write_state() { record_stage state; }
tx_rollback_apply() {
  record_stage rollback-apply
  printf 'rollback saw: %s\n' "$(cat "${TX_CONFIG}")" >> "${TX_LOG}"
}

@test "validation failure never enters apply" {
  printf 'old config\n' > "${TX_CONFIG}"
  printf '{"version":"old"}\n' > "${TX_STATE}"

  run mh_transaction_execute tx_preflight tx_resolve tx_backup tx_render tx_validate_fail tx_apply tx_health_ok tx_write_state

  [ "$status" -ne 0 ]
  run grep -F 'apply' "${TX_LOG}"
  [ "$status" -ne 0 ]
  [ "$(cat "${TX_CONFIG}")" = "old config" ]
}

@test "health failure restores old configuration and state" {
  printf 'old config\n' > "${TX_CONFIG}"
  printf '{"version":"old"}\n' > "${TX_STATE}"

  run mh_transaction_execute tx_preflight tx_resolve tx_backup tx_render tx_validate_ok tx_apply tx_health_fail tx_write_state

  [ "$status" -ne 0 ]
  [ "$(cat "${TX_CONFIG}")" = "old config" ]
  [ "$(cat "${TX_STATE}")" = '{"version":"old"}' ]
  run grep -F 'state' "${TX_LOG}"
  [ "$status" -ne 0 ]
}

@test "first install failure emits manual recovery guidance" {
  run mh_transaction_execute tx_preflight tx_resolve tx_backup tx_render tx_validate_ok tx_apply tx_health_fail tx_write_state

  [ "$status" -ne 0 ]
  [[ "$output" == *"manual recovery"* ]]
  [ ! -e "${TX_CONFIG}" ]
  [ ! -e "${TX_STATE}" ]
}

@test "dry-run skips backup apply health and state" {
  MH_DRY_RUN=1
  export MH_DRY_RUN

  mh_transaction_execute tx_preflight tx_resolve tx_backup tx_render tx_validate_ok tx_apply tx_health_ok tx_write_state

  [ "$(printf '%s ' $(cat "${TX_LOG}"))" = "preflight resolve render validate " ]
  [ ! -e "${TX_CONFIG}" ]
  [ ! -e "${TX_STATE}" ]
}

@test "failed health runs the deployment rollback callback after files are restored" {
  printf 'old config\n' > "${TX_CONFIG}"
  printf '{"version":"old"}\n' > "${TX_STATE}"

  run mh_transaction_execute tx_preflight tx_resolve tx_backup tx_render tx_validate_ok tx_apply tx_health_fail tx_write_state tx_rollback_apply

  [ "$status" -ne 0 ]
  run grep -F 'rollback saw: old config' "${TX_LOG}"
  [ "$status" -eq 0 ]
}
