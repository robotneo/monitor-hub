#!/usr/bin/env bash

MH_STACK_RUNTIME_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MH_STACK_RUNTIME_REPO_ROOT="$(cd "${MH_STACK_RUNTIME_LIB_DIR}/../.." && pwd -P)"
# shellcheck source=lib/core/transaction.sh disable=SC1091
source "${MH_STACK_RUNTIME_REPO_ROOT}/lib/core/transaction.sh"
# shellcheck source=lib/core/state.sh disable=SC1091
source "${MH_STACK_RUNTIME_REPO_ROOT}/lib/core/state.sh"

mh_stack_resolve_all_images() {
  MH_STACK_IMAGE_VARIABLES=()
  MH_STACK_VERSION_KEYS_SEEN=','
  export MH_STACK_VERSION_KEYS_SEEN
  if [[ -n "${MH_LC_ENTITY_DIR:-}" ]]; then
    mh_stack_validate_requested_version_keys "${MH_LC_ENTITY_DIR}/stack.yaml" || return 1
  fi
  stack_resolve_images || return 1
  mh_stack_validate_version_map
}

mh_stack_tx_preflight() {
  [[ "${MH_LC_MODE}" == "compose" && "${MH_LC_PROFILE}" == "single-node" ]]
}
mh_stack_tx_resolve() {
  if [[ "${MH_LC_ACTION}" == "restore" ]]; then
    mh_state_restore_images stack "${MH_LC_NAME}" || true
  fi
  mh_stack_resolve_all_images
}
mh_stack_tx_backup() {
  local state_path images_path
  state_path="$(mh_state_path stack "${MH_LC_NAME}")" || return 1
  images_path="$(mh_state_images_path stack "${MH_LC_NAME}")" || return 1
  mh_transaction_track "${MH_LC_CONFIG_ROOT}" || return 1
  mh_transaction_track "${state_path}" || return 1
  mh_transaction_track "${images_path}" || return 1
  if [[ "${MH_LC_ACTION}" == "restore" ]]; then
    mh_transaction_track "${MH_LC_DATA_ROOT}" || return 1
    mh_backup_create stack "${MH_LC_NAME}" \
      "${MH_LC_CONFIG_ROOT}" "${MH_LC_DATA_ROOT}" || return 1
    MH_LC_ROLLBACK_BACKUP="${MH_BACKUP_PATH}"
    export MH_LC_ROLLBACK_BACKUP
    return 0
  fi
  if [[ "${MH_LC_ACTION}" == "upgrade" && \
    ( -e "${MH_LC_CONFIG_ROOT}" || -e "${MH_LC_DATA_ROOT}" ) ]]; then
    mh_backup_create stack "${MH_LC_NAME}" "${MH_LC_CONFIG_ROOT}" "${MH_LC_DATA_ROOT}" || return 1
  fi
}
mh_stack_tx_render() {
  [[ "${MH_DRY_RUN:-0}" == "1" || "${MH_LC_ACTION}" == "restore" ]] && return 0
  stack_prepare_paths
}
mh_stack_tx_validate() {
  if [[ "${MH_LC_ACTION}" == "restore" ]]; then
    mh_backup_validate "${MH_RESTORE_PATH}" "${MH_LC_CONFIG_ROOT}" "${MH_LC_DATA_ROOT}"
  else
    mh_compose_run "${MH_LC_COMPOSE_DIR}" config
  fi
}
mh_stack_tx_apply() {
  [[ "${MH_LC_ACTION}" == "configure" ]] && return 0
  if [[ "${MH_LC_ACTION}" == "restore" ]]; then
    mh_compose_run "${MH_LC_COMPOSE_DIR}" stop || return 1
    mh_backup_restore "${MH_RESTORE_PATH}" "${MH_LC_CONFIG_ROOT}" "${MH_LC_DATA_ROOT}" || return 1
    mh_compose_run "${MH_LC_COMPOSE_DIR}" config || return 1
  fi
  mh_compose_run "${MH_LC_COMPOSE_DIR}" up -d
}
mh_stack_tx_health() {
  [[ "${MH_LC_ACTION}" == "configure" ]] && return 0
  mh_compose_wait_healthy "${MH_LC_COMPOSE_DIR}"
}
mh_stack_tx_state() {
  local state_input="${MH_TX_DIR}/deployment-state.json"
  printf '{"kind":"stack","name":"%s","mode":"compose","profile":"%s","version_policy":"%s","status":"healthy","updated_at":"%s"}\n' \
    "${MH_LC_NAME}" "${MH_LC_PROFILE}" "${MH_VERSION:-latest}" \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "${state_input}"
  mh_state_write stack "${MH_LC_NAME}" "${state_input}" || return 1
  mh_state_write_images stack "${MH_LC_NAME}" "${MH_STACK_IMAGE_VARIABLES[@]}"
}
mh_stack_tx_rollback_apply() {
  if [[ "${MH_LC_ACTION}" == "restore" && -n "${MH_LC_ROLLBACK_BACKUP:-}" ]]; then
    mh_backup_restore "${MH_LC_ROLLBACK_BACKUP}" \
      "${MH_LC_CONFIG_ROOT}" "${MH_LC_DATA_ROOT}" || return 1
  fi
  if mh_state_restore_images stack "${MH_LC_NAME}"; then
    mh_compose_run "${MH_LC_COMPOSE_DIR}" up -d || return 1
    mh_compose_wait_healthy "${MH_LC_COMPOSE_DIR}"
  else
    mh_compose_run "${MH_LC_COMPOSE_DIR}" down || true
    printf 'no previous stack image state exists; the failed first install was stopped\n' >&2
  fi
}
mh_stack_operational_context() {
  mh_state_restore_images stack "${MH_LC_NAME}" || true
  mh_stack_resolve_all_images
}

mh_stack_standard_lifecycle() {
  local stack_name="$1" stack_dir="$2" action="$3" mode="$4" profile="$5"
  local compose_dir="${stack_dir}/deploy/compose"
  if [[ "${mode}" != "compose" ]]; then
    printf 'unsupported deployment mode for %s: %s\n' "${stack_name}" "${mode}" >&2
    return 1
  fi
  if [[ "${profile}" != "single-node" ]]; then
    printf 'profile is documentation-only and cannot be deployed: %s\n' "${profile}" >&2
    return 1
  fi
  MH_CONFIG_DIR="${MH_CONFIG_DIR:-/etc/monitor-hub}"
  MH_DATA_DIR="${MH_DATA_DIR:-/var/lib/monitor-hub}"
  MH_STATE_DIR="${MH_STATE_DIR:-${MH_DATA_DIR}}"
  MH_LC_NAME="${stack_name}"
  MH_LC_ENTITY_DIR="${stack_dir}"
  MH_LC_COMPOSE_DIR="${compose_dir}"
  MH_LC_ACTION="${action}"
  MH_LC_MODE="${mode}"
  MH_LC_PROFILE="${profile}"
  MH_LC_CONFIG_ROOT="${MH_CONFIG_DIR}/stacks/${stack_name}"
  MH_LC_DATA_ROOT="${MH_DATA_DIR}/stacks/${stack_name}"
  MH_COMPOSE_FILES="${compose_dir}/compose.yaml"
  export MH_CONFIG_DIR MH_DATA_DIR MH_STATE_DIR MH_COMPOSE_FILES
  export MH_LC_NAME MH_LC_ENTITY_DIR MH_LC_COMPOSE_DIR MH_LC_ACTION MH_LC_MODE
  export MH_LC_PROFILE MH_LC_CONFIG_ROOT MH_LC_DATA_ROOT

  if [[ "${MH_DRY_RUN:-0}" == "1" ]]; then
    mh_stack_resolve_all_images || return 1
    mh_compose_run "${compose_dir}" config
    return $?
  fi

  case "${action}" in
    install | configure | upgrade | restore)
      if [[ "${action}" == "restore" && -z "${MH_RESTORE_PATH:-}" ]]; then
        printf 'MH_RESTORE_PATH is required for restore\n' >&2
        return 1
      fi
      mh_transaction_execute mh_stack_tx_preflight mh_stack_tx_resolve mh_stack_tx_backup \
        mh_stack_tx_render mh_stack_tx_validate mh_stack_tx_apply mh_stack_tx_health \
        mh_stack_tx_state mh_stack_tx_rollback_apply
      ;;
    validate) mh_stack_resolve_all_images && mh_compose_run "${compose_dir}" config ;;
    start)
      mh_stack_operational_context && mh_compose_run "${compose_dir}" up -d &&
        mh_compose_wait_healthy "${compose_dir}"
      ;;
    stop) mh_stack_operational_context && mh_compose_run "${compose_dir}" stop ;;
    restart)
      mh_stack_operational_context && mh_compose_run "${compose_dir}" restart &&
        mh_compose_wait_healthy "${compose_dir}"
      ;;
    status) mh_stack_operational_context && mh_compose_run "${compose_dir}" ps ;;
    doctor)
      mh_stack_operational_context && mh_compose_wait_healthy "${compose_dir}" &&
        mh_compose_assert_metrics_query "${compose_dir}"
      ;;
    backup) mh_backup_create stack "${stack_name}" "${MH_LC_CONFIG_ROOT}" "${MH_LC_DATA_ROOT}" ;;
    uninstall)
      mh_stack_operational_context || return 1
      if [[ "${MH_PURGE_DATA:-0}" == "1" ]]; then
        mh_compose_run "${compose_dir}" down --volumes || return 1
        mh_purge_managed_path "${MH_LC_CONFIG_ROOT}" "${MH_CONFIG_DIR}" || return 1
        mh_purge_managed_path "${MH_LC_DATA_ROOT}" "${MH_DATA_DIR}" || return 1
        mh_purge_managed_path "$(mh_state_path stack "${stack_name}")" "${MH_STATE_DIR}" || return 1
        mh_purge_managed_path "$(mh_state_images_path stack "${stack_name}")" "${MH_STATE_DIR}" || return 1
      else
        mh_compose_run "${compose_dir}" down
      fi
      ;;
    *) printf 'unsupported lifecycle action for %s: %s\n' "${stack_name}" "${action}" >&2; return 1 ;;
  esac
}
