#!/usr/bin/env bash

if [[ -n "${MH_COMPONENT_COMPOSE_LOADED:-}" ]]; then
  return 0
fi
MH_COMPONENT_COMPOSE_LOADED=1

mh_component_compose_context() {
  local component="$1"
  local image_variable="$2"
  local component_dir="$3"
  local image_value
  local repository_root

  MH_CONFIG_DIR="${MH_CONFIG_DIR:-/etc/monitor-hub}"
  MH_DATA_DIR="${MH_DATA_DIR:-/var/lib/monitor-hub}"
  export MH_CONFIG_DIR MH_DATA_DIR
  MH_COMPOSE_FILES="${component_dir}/deploy/compose/compose.yaml"
  export MH_COMPOSE_FILES

  image_value="$(eval "printf '%s' \"\${${image_variable}:-}\"")"
  if [[ -z "${image_value}" ]]; then
    repository_root="$(cd "${component_dir}/../.." && pwd -P)"
    if ! declare -F mh_resolve_image >/dev/null 2>&1; then
      # shellcheck source=lib/core/artifacts.sh disable=SC1091
      source "${repository_root}/lib/core/artifacts.sh"
    fi
    mh_resolve_image "${component}" "${MH_VERSION:-latest}" || return 1
    printf -v "${image_variable}" '%s' "${MH_IMAGE_REFERENCE}"
    export "${image_variable?}"
  fi
}

mh_component_prepare_paths() {
  local component="$1"
  local component_dir="$2"
  local source_file relative_file destination_file
  local target_config_dir="${MH_CONFIG_DIR}/${component}"
  local target_data_dir="${MH_DATA_DIR}/${component}"

  mkdir -p "${target_config_dir}" "${target_data_dir}"
  while IFS= read -r source_file; do
    relative_file="${source_file#"${component_dir}/config/"}"
    destination_file="${target_config_dir}/${relative_file}"
    mkdir -p "$(dirname "${destination_file}")"
    if [[ ! -e "${destination_file}" ]]; then
      cp "${source_file}" "${destination_file}"
    fi
  done < <(find "${component_dir}/config" -type f -print)
}

mh_component_compose_lifecycle() {
  local component="$1"
  local image_variable="$2"
  local component_dir="$3"
  local action="$4"
  local mode="$5"
  local compose_dir="${component_dir}/deploy/compose"

  if [[ "${mode}" != "compose" ]]; then
    printf 'unsupported deployment mode for %s: %s\n' "${component}" "${mode}" >&2
    return 1
  fi
  mh_component_compose_context "${component}" "${image_variable}" "${component_dir}" || return 1

  case "${action}" in
    validate | configure)
      mh_compose_run "${compose_dir}" config
      ;;
    install | start)
      if [[ "${action}" == "install" ]]; then
        mh_component_prepare_paths "${component}" "${component_dir}"
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
      mh_compose_run "${compose_dir}" pull
      mh_compose_run "${compose_dir}" up -d
      ;;
    backup)
      mh_backup_create component "${component}" \
        "${MH_CONFIG_DIR}/${component}" "${MH_DATA_DIR}/${component}"
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
      printf 'unsupported lifecycle action for %s: %s\n' "${component}" "${action}" >&2
      return 1
      ;;
  esac
}
