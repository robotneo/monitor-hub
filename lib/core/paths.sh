#!/usr/bin/env bash

if [[ -n "${MH_PATHS_LOADED:-}" ]]; then
  return 0
fi
MH_PATHS_LOADED=1

MH_PATHS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/core/constants.sh disable=SC1091
source "${MH_PATHS_LIB_DIR}/constants.sh"

mh_rooted_path() {
  local relative_path="$1"
  local root="${MH_ROOT_DIR:-${MH_DEFAULT_ROOT_DIR}}"
  root="${root%/}"
  printf '%s/%s\n' "${root}" "${relative_path#/}"
}

mh_init_paths() {
  MH_CONFIG_DIR="${MH_CONFIG_DIR:-$(mh_rooted_path /etc/monitor-hub)}"
  MH_DATA_DIR="${MH_DATA_DIR:-$(mh_rooted_path /var/lib/monitor-hub)}"
  MH_STATE_DIR="${MH_STATE_DIR:-${MH_DATA_DIR}}"
  MH_CACHE_DIR="${MH_CACHE_DIR:-$(mh_rooted_path /var/cache/monitor-hub)}"
  MH_LOG_DIR="${MH_LOG_DIR:-$(mh_rooted_path /var/log/monitor-hub)}"
  MH_BACKUP_DIR="${MH_BACKUP_DIR:-$(mh_rooted_path /var/backups/monitor-hub)}"

  export MH_CONFIG_DIR MH_DATA_DIR MH_STATE_DIR MH_CACHE_DIR MH_LOG_DIR MH_BACKUP_DIR
}
