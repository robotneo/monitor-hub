#!/usr/bin/env bash

if [[ -n "${MH_TRANSACTION_LOADED:-}" ]]; then
  return 0
fi
MH_TRANSACTION_LOADED=1

MH_TX_TRACKED_PATHS=()
MH_TX_TRACKED_EXISTED=()

mh_transaction_begin() {
  local root="${MH_TRANSACTION_ROOT:-${TMPDIR:-/tmp}/monitor-hub-transactions}"
  mkdir -p "${root}"
  MH_TX_DIR="$(mktemp -d "${root}/tx.XXXXXX")"
  MH_TX_TRACKED_PATHS=()
  MH_TX_TRACKED_EXISTED=()
  MH_TX_HAD_PREVIOUS_STATE=0
  export MH_TX_DIR MH_TX_HAD_PREVIOUS_STATE
}

mh_transaction_safe_target() {
  [[ -n "$1" && "$1" != "/" && "$1" != "." && "$1" != ".." ]]
}

mh_transaction_track() {
  local path="$1"
  local index="${#MH_TX_TRACKED_PATHS[@]}"
  local snapshot="${MH_TX_DIR}/snapshots/${index}"
  if ! mh_transaction_safe_target "${path}"; then
    printf 'unsafe transaction target: %s\n' "${path}" >&2
    return 1
  fi

  MH_TX_TRACKED_PATHS+=("${path}")
  mkdir -p "${MH_TX_DIR}/snapshots"
  if [[ -e "${path}" || -L "${path}" ]]; then
    MH_TX_TRACKED_EXISTED+=(1)
    MH_TX_HAD_PREVIOUS_STATE=1
    cp -R "${path}" "${snapshot}"
  else
    MH_TX_TRACKED_EXISTED+=(0)
  fi
  export MH_TX_HAD_PREVIOUS_STATE
}

mh_transaction_cleanup() {
  if [[ -n "${MH_TX_DIR:-}" && "${MH_TX_DIR}" == *'/tx.'* && -d "${MH_TX_DIR}" ]]; then
    rm -rf "${MH_TX_DIR}"
  fi
  MH_TX_DIR=""
  export MH_TX_DIR
}

mh_transaction_commit() {
  mh_transaction_cleanup
}

mh_transaction_rollback() {
  local index path snapshot parent
  for (( index = 0; index < ${#MH_TX_TRACKED_PATHS[@]}; index += 1 )); do
    path="${MH_TX_TRACKED_PATHS[${index}]}"
    snapshot="${MH_TX_DIR}/snapshots/${index}"
    mh_transaction_safe_target "${path}" || continue
    rm -rf "${path}"
    if [[ "${MH_TX_TRACKED_EXISTED[${index}]}" == "1" ]]; then
      parent="$(dirname "${path}")"
      mkdir -p "${parent}"
      cp -R "${snapshot}" "${path}"
    fi
  done
  if [[ "${MH_TX_HAD_PREVIOUS_STATE:-0}" == "0" ]]; then
    printf 'No previous deployment state was available; review diagnostics and complete manual recovery before retrying.\n' >&2
  fi
  mh_transaction_cleanup
}

mh_transaction_run_stage() {
  local callback="$1"
  if ! declare -F "${callback}" >/dev/null 2>&1; then
    printf 'transaction callback is not defined: %s\n' "${callback}" >&2
    return 1
  fi
  "${callback}"
}

mh_transaction_execute() {
  local preflight="$1" resolve="$2" backup="$3" render="$4"
  local validate="$5" apply="$6" health="$7" state="$8"

  mh_transaction_begin || return 1
  if ! mh_transaction_run_stage "${preflight}" || ! mh_transaction_run_stage "${resolve}"; then
    mh_transaction_rollback
    return 1
  fi

  if [[ "${MH_DRY_RUN:-0}" == "1" ]]; then
    if ! mh_transaction_run_stage "${render}" || ! mh_transaction_run_stage "${validate}"; then
      mh_transaction_rollback
      return 1
    fi
    mh_transaction_commit
    return 0
  fi

  if ! mh_transaction_run_stage "${backup}" || \
    ! mh_transaction_run_stage "${render}" || \
    ! mh_transaction_run_stage "${validate}"; then
    mh_transaction_rollback
    return 1
  fi
  if ! mh_transaction_run_stage "${apply}" || \
    ! mh_transaction_run_stage "${health}" || \
    ! mh_transaction_run_stage "${state}"; then
    mh_transaction_rollback
    return 1
  fi
  mh_transaction_commit
}
