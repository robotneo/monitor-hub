#!/usr/bin/env bash

MH_N9E_STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MH_N9E_REPO_ROOT="$(cd "${MH_N9E_STACK_DIR}/../.." && pwd -P)"
# shellcheck source=lib/core/stack-compose.sh disable=SC1091
source "${MH_N9E_REPO_ROOT}/lib/core/stack-compose.sh"

stack_resolve_images() {
  mh_stack_require_component_image categraf CATEGRAF_IMAGE || return 1
  mh_stack_require_component_image nightingale NIGHTINGALE_IMAGE || return 1
  mh_stack_require_component_image victoriametrics VICTORIAMETRICS_IMAGE || return 1
  mh_stack_require_component_image grafana GRAFANA_IMAGE || return 1
  mh_stack_require_external_image "${MYSQL_BASE_IMAGE:-mysql:8.4.8}" MYSQL_IMAGE || return 1
  mh_stack_require_external_image "${REDIS_BASE_IMAGE:-redis:8.6.7-alpine}" REDIS_IMAGE
}

stack_prepare_paths() {
  local root="${MH_CONFIG_DIR}/stacks/nightingale-monitoring"
  local secrets="${root}/secrets"
  local data="${MH_DATA_DIR}/stacks/nightingale-monitoring"
  local mysql_password config_file service

  mh_stack_copy_config_tree "${MH_N9E_STACK_DIR}/config" "${root}"
  mh_stack_generate_secret "${secrets}/mysql-root-password" || return 1
  mh_stack_generate_secret "${secrets}/mysql-password" || return 1
  mh_stack_generate_secret "${secrets}/grafana-admin-password" || return 1
  mh_stack_generate_secret "${secrets}/nightingale-bootstrap-password" || return 1
  for service in mysql redis victoriametrics nightingale categraf grafana; do mkdir -p "${data}/${service}"; done

  config_file="${root}/nightingale/config.toml"
  if [[ ! -e "${config_file}" ]]; then
    mysql_password="$(<"${secrets}/mysql-password")"
    sed "s/__MYSQL_PASSWORD__/${mysql_password}/g" \
      "${root}/nightingale/config.toml.template" > "${config_file}"
    chmod 0600 "${config_file}"
  fi
}

stack_lifecycle() {
  MH_COMPONENTS_DIR="${MH_COMPONENTS_DIR:-${MH_N9E_REPO_ROOT}/components}"
  MH_CONFIG_DIR="${MH_CONFIG_DIR:-/etc/monitor-hub}"
  MH_DATA_DIR="${MH_DATA_DIR:-/var/lib/monitor-hub}"
  export MH_COMPONENTS_DIR MH_CONFIG_DIR MH_DATA_DIR
  mh_stack_standard_lifecycle nightingale-monitoring "${MH_N9E_STACK_DIR}" "$@"
}
