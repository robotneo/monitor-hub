#!/usr/bin/env bash

MH_VM_STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MH_VM_STACK_REPO_ROOT="$(cd "${MH_VM_STACK_DIR}/../.." && pwd -P)"

# shellcheck source=lib/adapters/compose.sh disable=SC1091
source "${MH_VM_STACK_REPO_ROOT}/lib/adapters/compose.sh"
# shellcheck source=lib/core/artifacts.sh disable=SC1091
source "${MH_VM_STACK_REPO_ROOT}/lib/core/artifacts.sh"
# shellcheck source=lib/core/backup.sh disable=SC1091
source "${MH_VM_STACK_REPO_ROOT}/lib/core/backup.sh"

mh_vm_stack_require_pinned_image() {
  local component="$1"
  local variable="$2"
  local value
  value="$(eval "printf '%s' \"\${${variable}:-}\"")"

  if [[ -z "${value}" ]]; then
    mh_resolve_image "${component}" latest || return 1
    printf -v "${variable}" '%s' "${MH_IMAGE_DIGEST}"
    export "${variable?}"
    return 0
  fi
  if [[ "${value}" == *:latest || ( "${value}" != *@sha256:* && "${value##*/}" != *:* ) ]]; then
    printf '%s must use an exact tag or immutable digest, got: %s\n' "${variable}" "${value}" >&2
    return 1
  fi
}

mh_vm_stack_resolve_images() {
  mh_vm_stack_require_pinned_image blackbox-exporter BLACKBOX_EXPORTER_IMAGE || return 1
  mh_vm_stack_require_pinned_image vmware-exporter VMWARE_EXPORTER_IMAGE || return 1
  mh_vm_stack_require_pinned_image vmagent VMAGENT_IMAGE || return 1
  mh_vm_stack_require_pinned_image victoriametrics VICTORIAMETRICS_IMAGE || return 1
  mh_vm_stack_require_pinned_image grafana GRAFANA_IMAGE || return 1
  mh_vm_stack_require_pinned_image vmalert VMALERT_IMAGE || return 1
  mh_vm_stack_require_pinned_image alertmanager ALERTMANAGER_IMAGE
}

mh_vm_stack_copy_config() {
  local target_root="${MH_CONFIG_DIR}/stacks/victoriametrics-monitoring"
  local source_file relative_file target_file

  mkdir -p "${target_root}"
  while IFS= read -r source_file; do
    relative_file="${source_file#"${MH_VM_STACK_DIR}/config/"}"
    target_file="${target_root}/${relative_file}"
    mkdir -p "$(dirname "${target_file}")"
    if [[ ! -e "${target_file}" ]]; then
      cp "${source_file}" "${target_file}"
    fi
  done < <(find "${MH_VM_STACK_DIR}/config" -type f -print)
}

mh_vm_stack_prepare_paths() {
  local stack_root="${MH_DATA_DIR}/stacks/victoriametrics-monitoring"
  local secret_dir="${MH_CONFIG_DIR}/stacks/victoriametrics-monitoring/secrets"
  local secret_file="${secret_dir}/grafana-admin-password"
  local service

  mh_vm_stack_copy_config
  for service in victoriametrics vmagent alertmanager grafana; do
    mkdir -p "${stack_root}/${service}"
  done
  mkdir -p "${secret_dir}"
  if [[ ! -e "${secret_file}" ]]; then
    if ! command -v openssl >/dev/null 2>&1; then
      printf 'openssl is required to generate the Grafana admin secret\n' >&2
      return 1
    fi
    (umask 077; openssl rand -hex 24 > "${secret_file}")
  fi
  chmod 0600 "${secret_file}"
}

stack_lifecycle() {
  local action="$1"
  local mode="$2"
  local profile="$3"
  local compose_dir="${MH_VM_STACK_DIR}/deploy/compose"
  local config_root data_root

  if [[ "${mode}" != "compose" ]]; then
    printf 'unsupported deployment mode for victoriametrics-monitoring: %s\n' "${mode}" >&2
    return 1
  fi
  if [[ "${profile}" != "single-node" ]]; then
    printf 'profile is documentation-only and cannot be deployed: %s\n' "${profile}" >&2
    return 1
  fi

  MH_COMPONENTS_DIR="${MH_COMPONENTS_DIR:-${MH_VM_STACK_REPO_ROOT}/components}"
  MH_CONFIG_DIR="${MH_CONFIG_DIR:-/etc/monitor-hub}"
  MH_DATA_DIR="${MH_DATA_DIR:-/var/lib/monitor-hub}"
  MH_COMPOSE_FILES="${compose_dir}/compose.yaml"
  VMWARE_CONFIG_FILE="${VMWARE_CONFIG_FILE:-${MH_CONFIG_DIR}/stacks/victoriametrics-monitoring/vmware-exporter/config.yml}"
  export MH_COMPONENTS_DIR MH_CONFIG_DIR MH_DATA_DIR MH_COMPOSE_FILES VMWARE_CONFIG_FILE

  mh_vm_stack_resolve_images || return 1
  config_root="${MH_CONFIG_DIR}/stacks/victoriametrics-monitoring"
  data_root="${MH_DATA_DIR}/stacks/victoriametrics-monitoring"

  case "${action}" in
    validate)
      mh_compose_run "${compose_dir}" config
      ;;
    configure)
      mh_vm_stack_prepare_paths && mh_compose_run "${compose_dir}" config
      ;;
    install | start)
      if [[ "${action}" == "install" ]]; then
        mh_vm_stack_prepare_paths || return 1
      fi
      mh_compose_run "${compose_dir}" up -d
      ;;
    stop)
      mh_compose_run "${compose_dir}" stop
      ;;
    restart)
      mh_compose_run "${compose_dir}" restart
      ;;
    status | doctor)
      mh_compose_run "${compose_dir}" ps
      ;;
    upgrade)
      mh_compose_run "${compose_dir}" pull && mh_compose_run "${compose_dir}" up -d
      ;;
    backup)
      mh_backup_create stack victoriametrics-monitoring "${config_root}" "${data_root}"
      ;;
    restore)
      if [[ -z "${MH_RESTORE_PATH:-}" ]]; then
        printf 'MH_RESTORE_PATH is required for restore\n' >&2
        return 1
      fi
      mh_backup_restore "${MH_RESTORE_PATH}"
      ;;
    uninstall)
      if [[ "${MH_PURGE_DATA:-0}" == "1" ]]; then
        mh_compose_run "${compose_dir}" down --volumes
      else
        mh_compose_run "${compose_dir}" down
      fi
      ;;
    *)
      printf 'unsupported lifecycle action for victoriametrics-monitoring: %s\n' "${action}" >&2
      return 1
      ;;
  esac
}
