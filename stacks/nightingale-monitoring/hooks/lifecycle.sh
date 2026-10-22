#!/usr/bin/env bash

MH_N9E_STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MH_N9E_REPO_ROOT="$(cd "${MH_N9E_STACK_DIR}/../.." && pwd -P)"
# shellcheck source=lib/core/stack-compose.sh disable=SC1091
source "${MH_N9E_REPO_ROOT}/lib/core/stack-compose.sh"
# shellcheck source=components/nightingale/hooks/assets.sh disable=SC1091
source "${MH_N9E_REPO_ROOT}/components/nightingale/hooks/assets.sh"

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
  local mysql_password config_file

  mh_stack_copy_config_tree "${MH_N9E_STACK_DIR}/config" "${root}"
  mh_stack_generate_secret "${secrets}/mysql-root-password" 0 0 || return 1
  mh_stack_generate_secret "${secrets}/mysql-password" 0 0 || return 1
  mh_stack_generate_secret "${secrets}/grafana-admin-password" 472 472 || return 1
  mh_ensure_service_directory "${data}/mysql" 999 999 0750 || return 1
  mh_ensure_service_directory "${data}/redis" 999 999 0750 || return 1
  mh_ensure_service_directory "${data}/victoriametrics" 1000 1000 0750 || return 1
  mh_ensure_service_directory "${data}/nightingale" 0 0 0750 || return 1
  mh_ensure_service_directory "${data}/categraf" 1000 1000 0750 || return 1
  mh_ensure_service_directory "${data}/grafana" 472 472 0750 || return 1

  if [[ -z "${NIGHTINGALE_VERSION:-}" ]]; then
    printf 'NIGHTINGALE_VERSION is required when NIGHTINGALE_IMAGE is supplied by digest\n' >&2
    return 1
  fi
  nightingale_prepare_release_assets "${NIGHTINGALE_VERSION}" "${root}/nightingale/upstream" || return 1
  mkdir -p "${root}/mysql-init"
  cp "${root}/nightingale/upstream/n9e.sql" "${root}/mysql-init/01-n9e.sql"
  printf '%s  %s\n' "$(mh_sha256_file "${root}/mysql-init/01-n9e.sql")" '01-n9e.sql' \
    > "${root}/mysql-init/checksums.sha256"

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
