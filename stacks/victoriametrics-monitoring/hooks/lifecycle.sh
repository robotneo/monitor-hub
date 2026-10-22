#!/usr/bin/env bash

MH_VM_STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MH_VM_STACK_REPO_ROOT="$(cd "${MH_VM_STACK_DIR}/../.." && pwd -P)"

# shellcheck source=lib/adapters/compose.sh disable=SC1091
source "${MH_VM_STACK_REPO_ROOT}/lib/adapters/compose.sh"
# shellcheck source=lib/core/artifacts.sh disable=SC1091
source "${MH_VM_STACK_REPO_ROOT}/lib/core/artifacts.sh"
# shellcheck source=lib/core/backup.sh disable=SC1091
source "${MH_VM_STACK_REPO_ROOT}/lib/core/backup.sh"
# shellcheck source=lib/core/stack-compose.sh disable=SC1091
source "${MH_VM_STACK_REPO_ROOT}/lib/core/stack-compose.sh"

stack_resolve_images() {
  mh_stack_require_component_image blackbox-exporter BLACKBOX_EXPORTER_IMAGE || return 1
  mh_stack_require_component_image vmware-exporter VMWARE_EXPORTER_IMAGE || return 1
  mh_stack_require_component_image vmagent VMAGENT_IMAGE || return 1
  mh_stack_require_component_image victoriametrics VICTORIAMETRICS_IMAGE || return 1
  mh_stack_require_component_image grafana GRAFANA_IMAGE || return 1
  mh_stack_require_component_image vmalert VMALERT_IMAGE || return 1
  mh_stack_require_component_image alertmanager ALERTMANAGER_IMAGE
}

stack_prepare_paths() {
  local stack_root="${MH_DATA_DIR}/stacks/victoriametrics-monitoring"
  local secret_file="${MH_CONFIG_DIR}/stacks/victoriametrics-monitoring/secrets/grafana-admin-password"
  mh_vm_stack_copy_config
  mh_ensure_service_directory "${stack_root}/victoriametrics" 1000 1000 0750 || return 1
  mh_ensure_service_directory "${stack_root}/vmagent" 1000 1000 0750 || return 1
  mh_ensure_service_directory "${stack_root}/alertmanager" 65534 65534 0750 || return 1
  mh_ensure_service_directory "${stack_root}/grafana" 472 472 0750 || return 1
  mh_stack_generate_secret "${secret_file}" 472 472
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

stack_lifecycle() {
  MH_COMPONENTS_DIR="${MH_COMPONENTS_DIR:-${MH_VM_STACK_REPO_ROOT}/components}"
  MH_CONFIG_DIR="${MH_CONFIG_DIR:-/etc/monitor-hub}"
  MH_DATA_DIR="${MH_DATA_DIR:-/var/lib/monitor-hub}"
  VMWARE_CONFIG_FILE="${VMWARE_CONFIG_FILE:-${MH_CONFIG_DIR}/stacks/victoriametrics-monitoring/vmware-exporter/config.yml}"
  export MH_COMPONENTS_DIR MH_CONFIG_DIR MH_DATA_DIR VMWARE_CONFIG_FILE
  mh_stack_standard_lifecycle victoriametrics-monitoring "${MH_VM_STACK_DIR}" "$@"
}
