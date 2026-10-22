#!/usr/bin/env bash

MH_COMPONENT_RUNTIME_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MH_COMPONENT_RUNTIME_REPO_ROOT="$(cd "${MH_COMPONENT_RUNTIME_LIB_DIR}/../.." && pwd -P)"
# shellcheck source=lib/core/transaction.sh disable=SC1091
source "${MH_COMPONENT_RUNTIME_REPO_ROOT}/lib/core/transaction.sh"
# shellcheck source=lib/core/state.sh disable=SC1091
source "${MH_COMPONENT_RUNTIME_REPO_ROOT}/lib/core/state.sh"
# shellcheck source=lib/core/runtime-paths.sh disable=SC1091
source "${MH_COMPONENT_RUNTIME_REPO_ROOT}/lib/core/runtime-paths.sh"

mh_component_compose_context() {
  local component="$1" image_variable="$2" component_dir="$3"
  local image_value repository_root
  MH_CONFIG_DIR="${MH_CONFIG_DIR:-/etc/monitor-hub}"
  MH_DATA_DIR="${MH_DATA_DIR:-/var/lib/monitor-hub}"
  MH_STATE_DIR="${MH_STATE_DIR:-${MH_DATA_DIR}}"
  MH_COMPOSE_FILES="${MH_COMPOSE_FILES:-${component_dir}/deploy/compose/compose.yaml}"
  export MH_CONFIG_DIR MH_DATA_DIR MH_STATE_DIR MH_COMPOSE_FILES

  image_value="${!image_variable:-}"
  repository_root="$(cd "${component_dir}/../.." && pwd -P)"
  if ! declare -F mh_resolve_image >/dev/null 2>&1; then
    # shellcheck source=lib/core/artifacts.sh disable=SC1091
    source "${repository_root}/lib/core/artifacts.sh"
  fi
  if [[ -z "${image_value}" ]]; then
    mh_resolve_image "${component}" "${MH_VERSION:-latest}" || return 1
    printf -v "${image_variable}" '%s' "${MH_IMAGE_DIGEST:-${MH_IMAGE_REFERENCE}}"
  else
    mh_resolve_image_reference "${image_value}" || return 1
    printf -v "${image_variable}" '%s' "${MH_RESOLVED_IMAGE}"
  fi
  export "${image_variable?}"
}

mh_component_identity() {
  case "$1" in
    prometheus | alertmanager | blackbox-exporter | vmware-exporter) printf '65534:65534\n' ;;
    grafana) printf '472:472\n' ;;
    victoriametrics | vmagent | vmalert | categraf) printf '1000:1000\n' ;;
    *) printf '0:0\n' ;;
  esac
}

mh_component_prepare_paths() {
  local component="$1" component_dir="$2"
  local source_file relative_file destination_file identity uid gid
  local target_config_dir="${MH_CONFIG_DIR}/${component}"
  local target_data_dir="${MH_DATA_DIR}/${component}"
  mkdir -p "${target_config_dir}"
  while IFS= read -r source_file; do
    relative_file="${source_file#"${component_dir}/config/"}"
    destination_file="${target_config_dir}/${relative_file}"
    mkdir -p "$(dirname "${destination_file}")"
    [[ -e "${destination_file}" ]] || cp "${source_file}" "${destination_file}"
  done < <(find "${component_dir}/config" -type f -print)

  identity="$(mh_component_identity "${component}")"
  uid="${identity%%:*}"
  gid="${identity#*:}"
  mh_ensure_service_directory "${target_data_dir}" "${uid}" "${gid}" 0750 || return 1
  if [[ "${component}" == "grafana" ]]; then
    mkdir -p "${target_config_dir}/secrets"
    if [[ ! -e "${target_config_dir}/secrets/admin-password" ]]; then
      command -v openssl >/dev/null 2>&1 || {
        printf 'openssl is required to generate the Grafana admin secret\n' >&2
        return 1
      }
      (umask 077; openssl rand -hex 24 > "${target_config_dir}/secrets/admin-password")
    fi
    mh_secure_service_file "${target_config_dir}/secrets/admin-password" 472 472 0400
  fi
}

mh_component_tx_preflight() { [[ "${MH_LC_MODE}" == "compose" ]]; }
mh_component_tx_resolve() {
  if [[ "${MH_LC_ACTION}" == "restore" ]]; then
    mh_state_restore_images component "${MH_LC_NAME}" || true
  fi
  mh_component_compose_context "${MH_LC_NAME}" "${MH_LC_IMAGE_VARIABLE}" "${MH_LC_ENTITY_DIR}"
}
mh_component_tx_backup() {
  local state_path images_path
  state_path="$(mh_state_path component "${MH_LC_NAME}")" || return 1
  images_path="$(mh_state_images_path component "${MH_LC_NAME}")" || return 1
  mh_transaction_track "${MH_LC_CONFIG_ROOT}" || return 1
  mh_transaction_track "${state_path}" || return 1
  mh_transaction_track "${images_path}" || return 1
  if [[ "${MH_LC_ACTION}" == "restore" ]]; then
    mh_transaction_track "${MH_LC_DATA_ROOT}" || return 1
    mh_backup_create component "${MH_LC_NAME}" \
      "${MH_LC_CONFIG_ROOT}" "${MH_LC_DATA_ROOT}" || return 1
    MH_LC_ROLLBACK_BACKUP="${MH_BACKUP_PATH}"
    export MH_LC_ROLLBACK_BACKUP
    return 0
  fi
  if [[ "${MH_LC_ACTION}" == "upgrade" && \
    ( -e "${MH_LC_CONFIG_ROOT}" || -e "${MH_LC_DATA_ROOT}" ) ]]; then
    mh_backup_create component "${MH_LC_NAME}" "${MH_LC_CONFIG_ROOT}" "${MH_LC_DATA_ROOT}" || return 1
  fi
}
mh_component_tx_render() {
  [[ "${MH_DRY_RUN:-0}" == "1" || "${MH_LC_ACTION}" == "restore" ]] && return 0
  mh_component_prepare_paths "${MH_LC_NAME}" "${MH_LC_ENTITY_DIR}"
}
mh_component_tx_validate() {
  if [[ "${MH_LC_ACTION}" == "restore" ]]; then
    mh_backup_validate "${MH_RESTORE_PATH}" "${MH_LC_CONFIG_ROOT}" "${MH_LC_DATA_ROOT}"
  else
    mh_compose_run "${MH_LC_COMPOSE_DIR}" config
  fi
}
mh_component_tx_apply() {
  [[ "${MH_LC_ACTION}" == "configure" ]] && return 0
  if [[ "${MH_LC_ACTION}" == "restore" ]]; then
    mh_compose_run "${MH_LC_COMPOSE_DIR}" stop || return 1
    mh_backup_restore "${MH_RESTORE_PATH}" "${MH_LC_CONFIG_ROOT}" "${MH_LC_DATA_ROOT}" || return 1
    mh_compose_run "${MH_LC_COMPOSE_DIR}" config || return 1
  fi
  mh_compose_run "${MH_LC_COMPOSE_DIR}" up -d
}
mh_component_tx_health() {
  [[ "${MH_LC_ACTION}" == "configure" ]] && return 0
  mh_compose_wait_healthy "${MH_LC_COMPOSE_DIR}"
}
mh_component_tx_state() {
  local state_input="${MH_TX_DIR}/deployment-state.json"
  local image_value="${!MH_LC_IMAGE_VARIABLE}"
  printf '{"kind":"component","name":"%s","mode":"compose","version":"%s","image":"%s","status":"healthy","updated_at":"%s"}\n' \
    "${MH_LC_NAME}" "${MH_IMAGE_VERSION:-${MH_VERSION:-configured}}" "${image_value}" \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "${state_input}"
  mh_state_write component "${MH_LC_NAME}" "${state_input}" || return 1
  mh_state_write_images component "${MH_LC_NAME}" "${MH_LC_IMAGE_VARIABLE}"
}
mh_component_tx_rollback_apply() {
  if [[ "${MH_LC_ACTION}" == "restore" && -n "${MH_LC_ROLLBACK_BACKUP:-}" ]]; then
    mh_backup_restore "${MH_LC_ROLLBACK_BACKUP}" \
      "${MH_LC_CONFIG_ROOT}" "${MH_LC_DATA_ROOT}" || return 1
  fi
  if mh_state_restore_images component "${MH_LC_NAME}"; then
    mh_compose_run "${MH_LC_COMPOSE_DIR}" up -d || return 1
    mh_compose_wait_healthy "${MH_LC_COMPOSE_DIR}"
  else
    mh_compose_run "${MH_LC_COMPOSE_DIR}" down || true
    printf 'no previous component image state exists; the failed first install was stopped\n' >&2
  fi
}
mh_component_operational_context() {
  if [[ -z "${!MH_LC_IMAGE_VARIABLE:-}" ]]; then
    mh_state_restore_images component "${MH_LC_NAME}" || true
  fi
  mh_component_compose_context "${MH_LC_NAME}" "${MH_LC_IMAGE_VARIABLE}" "${MH_LC_ENTITY_DIR}"
}

mh_component_compose_lifecycle() {
  local component="$1" image_variable="$2" component_dir="$3" action="$4" mode="$5"
  if [[ "${mode}" != "compose" ]]; then
    printf 'unsupported deployment mode for %s: %s\n' "${component}" "${mode}" >&2
    return 1
  fi
  MH_LC_NAME="${component}"
  MH_LC_IMAGE_VARIABLE="${image_variable}"
  MH_LC_ENTITY_DIR="${component_dir}"
  MH_LC_COMPOSE_DIR="${component_dir}/deploy/compose"
  MH_LC_ACTION="${action}"
  MH_LC_MODE="${mode}"
  MH_CONFIG_DIR="${MH_CONFIG_DIR:-/etc/monitor-hub}"
  MH_DATA_DIR="${MH_DATA_DIR:-/var/lib/monitor-hub}"
  MH_STATE_DIR="${MH_STATE_DIR:-${MH_DATA_DIR}}"
  MH_LC_CONFIG_ROOT="${MH_CONFIG_DIR}/${component}"
  MH_LC_DATA_ROOT="${MH_DATA_DIR}/${component}"
  MH_COMPOSE_FILES="${MH_COMPOSE_FILES:-${component_dir}/deploy/compose/compose.yaml}"
  export MH_CONFIG_DIR MH_DATA_DIR MH_STATE_DIR MH_COMPOSE_FILES
  export MH_LC_NAME MH_LC_IMAGE_VARIABLE MH_LC_ENTITY_DIR MH_LC_COMPOSE_DIR
  export MH_LC_ACTION MH_LC_MODE MH_LC_CONFIG_ROOT MH_LC_DATA_ROOT

  if [[ "${MH_DRY_RUN:-0}" == "1" ]]; then
    mh_component_compose_context "${component}" "${image_variable}" "${component_dir}" || return 1
    mh_compose_run "${MH_LC_COMPOSE_DIR}" config
    return $?
  fi

  case "${action}" in
    install | configure | upgrade | restore)
      if [[ "${action}" == "restore" && -z "${MH_RESTORE_PATH:-}" ]]; then
        printf 'MH_RESTORE_PATH is required for restore\n' >&2
        return 1
      fi
      mh_transaction_execute mh_component_tx_preflight mh_component_tx_resolve \
        mh_component_tx_backup mh_component_tx_render mh_component_tx_validate \
        mh_component_tx_apply mh_component_tx_health mh_component_tx_state \
        mh_component_tx_rollback_apply
      ;;
    validate)
      mh_component_compose_context "${component}" "${image_variable}" "${component_dir}" &&
        mh_compose_run "${MH_LC_COMPOSE_DIR}" config
      ;;
    start)
      mh_component_operational_context && mh_compose_run "${MH_LC_COMPOSE_DIR}" up -d &&
        mh_compose_wait_healthy "${MH_LC_COMPOSE_DIR}"
      ;;
    stop) mh_component_operational_context && mh_compose_run "${MH_LC_COMPOSE_DIR}" stop ;;
    restart)
      mh_component_operational_context && mh_compose_run "${MH_LC_COMPOSE_DIR}" restart &&
        mh_compose_wait_healthy "${MH_LC_COMPOSE_DIR}"
      ;;
    status) mh_component_operational_context && mh_compose_run "${MH_LC_COMPOSE_DIR}" ps ;;
    doctor) mh_component_operational_context && mh_compose_wait_healthy "${MH_LC_COMPOSE_DIR}" ;;
    backup) mh_backup_create component "${component}" "${MH_LC_CONFIG_ROOT}" "${MH_LC_DATA_ROOT}" ;;
    uninstall)
      mh_component_operational_context || return 1
      if [[ "${MH_PURGE_DATA:-0}" == "1" ]]; then
        mh_compose_run "${MH_LC_COMPOSE_DIR}" down --volumes || return 1
        mh_purge_managed_path "${MH_LC_CONFIG_ROOT}" "${MH_CONFIG_DIR}" || return 1
        mh_purge_managed_path "${MH_LC_DATA_ROOT}" "${MH_DATA_DIR}" || return 1
        mh_purge_managed_path "$(mh_state_path component "${component}")" "${MH_STATE_DIR}" || return 1
        mh_purge_managed_path "$(mh_state_images_path component "${component}")" "${MH_STATE_DIR}" || return 1
      else
        mh_compose_run "${MH_LC_COMPOSE_DIR}" down
      fi
      ;;
    *) printf 'unsupported lifecycle action for %s: %s\n' "${component}" "${action}" >&2; return 1 ;;
  esac
}
