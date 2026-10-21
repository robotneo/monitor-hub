#!/usr/bin/env bash

if [[ -n "${MH_STACK_COMPOSE_LOADED:-}" ]]; then
  return 0
fi
MH_STACK_COMPOSE_LOADED=1

MH_STACK_COMPOSE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MH_STACK_COMPOSE_REPO_ROOT="$(cd "${MH_STACK_COMPOSE_LIB_DIR}/../.." && pwd -P)"
# shellcheck source=lib/adapters/compose.sh disable=SC1091
source "${MH_STACK_COMPOSE_REPO_ROOT}/lib/adapters/compose.sh"
# shellcheck source=lib/core/artifacts.sh disable=SC1091
source "${MH_STACK_COMPOSE_REPO_ROOT}/lib/core/artifacts.sh"
# shellcheck source=lib/core/backup.sh disable=SC1091
source "${MH_STACK_COMPOSE_REPO_ROOT}/lib/core/backup.sh"

mh_stack_image_is_pinned() {
  local value="$1"
  [[ -n "${value}" && "${value}" != *:latest && \
    ( "${value}" == *@sha256:* || "${value##*/}" == *:* ) ]]
}

mh_stack_require_component_image() {
  local component="$1" variable="$2" value
  value="$(eval "printf '%s' \"\${${variable}:-}\"")"
  if [[ -n "${value}" ]]; then
    if ! mh_stack_image_is_pinned "${value}"; then
      printf '%s must use an exact tag or immutable digest, got: %s\n' "${variable}" "${value}" >&2
      return 1
    fi
    return 0
  fi
  mh_resolve_image "${component}" latest || return 1
  printf -v "${variable}" '%s' "${MH_IMAGE_DIGEST}"
  export "${variable?}"
}

mh_stack_require_external_image() {
  local default_reference="$1" variable="$2" value digest
  local docker_bin="${MH_DOCKER_BIN:-docker}"
  value="$(eval "printf '%s' \"\${${variable}:-${default_reference}}\"")"
  if ! mh_stack_image_is_pinned "${value}"; then
    printf '%s must use an exact tag or immutable digest, got: %s\n' "${variable}" "${value}" >&2
    return 1
  fi
  if [[ "${value}" == *@sha256:* ]]; then
    printf -v "${variable}" '%s' "${value}"
    export "${variable?}"
    return 0
  fi
  if ! digest="$("${docker_bin}" image inspect "${value}" --format '{{index .RepoDigests 0}}' 2>/dev/null)"; then
    if ! "${docker_bin}" pull "${value}"; then
      printf 'unable to pull supporting image %s; load it locally or configure a registry mirror and retry\n' \
        "${value}" >&2
      return 1
    fi
    digest="$("${docker_bin}" image inspect "${value}" --format '{{index .RepoDigests 0}}' 2>/dev/null)" || return 1
  fi
  [[ -n "${digest}" ]] || { printf 'supporting image has no immutable digest: %s\n' "${value}" >&2; return 1; }
  printf -v "${variable}" '%s' "${digest}"
  export "${variable?}"
}

mh_stack_copy_config_tree() {
  local source_root="$1" target_root="$2" source_file relative_file target_file
  mkdir -p "${target_root}"
  while IFS= read -r source_file; do
    relative_file="${source_file#"${source_root}/"}"
    target_file="${target_root}/${relative_file}"
    mkdir -p "$(dirname "${target_file}")"
    [[ -e "${target_file}" ]] || cp "${source_file}" "${target_file}"
  done < <(find "${source_root}" -type f -print)
}

mh_stack_generate_secret() {
  local path="$1"
  mkdir -p "$(dirname "${path}")"
  if [[ ! -e "${path}" ]]; then
    command -v openssl >/dev/null 2>&1 || { printf 'openssl is required to generate runtime secrets\n' >&2; return 1; }
    (umask 077; openssl rand -hex 24 > "${path}")
  fi
  chmod 0600 "${path}"
}

mh_stack_standard_lifecycle() {
  local stack_name="$1" stack_dir="$2" action="$3" mode="$4" profile="$5"
  local compose_dir="${stack_dir}/deploy/compose"
  local config_root="${MH_CONFIG_DIR}/stacks/${stack_name}"
  local data_root="${MH_DATA_DIR}/stacks/${stack_name}"

  [[ "${mode}" == "compose" ]] || { printf 'unsupported deployment mode for %s: %s\n' "${stack_name}" "${mode}" >&2; return 1; }
  [[ "${profile}" == "single-node" ]] || { printf 'profile is documentation-only and cannot be deployed: %s\n' "${profile}" >&2; return 1; }
  MH_COMPOSE_FILES="${compose_dir}/compose.yaml"
  export MH_COMPOSE_FILES
  stack_resolve_images || return 1

  case "${action}" in
    validate) mh_compose_run "${compose_dir}" config ;;
    configure) stack_prepare_paths && mh_compose_run "${compose_dir}" config ;;
    install | start)
      [[ "${action}" != "install" ]] || stack_prepare_paths || return 1
      mh_compose_run "${compose_dir}" up -d
      ;;
    stop) mh_compose_run "${compose_dir}" stop ;;
    restart) mh_compose_run "${compose_dir}" restart ;;
    status | doctor) mh_compose_run "${compose_dir}" ps ;;
    upgrade) mh_compose_run "${compose_dir}" pull && mh_compose_run "${compose_dir}" up -d ;;
    backup) mh_backup_create stack "${stack_name}" "${config_root}" "${data_root}" ;;
    restore)
      [[ -n "${MH_RESTORE_PATH:-}" ]] || { printf 'MH_RESTORE_PATH is required for restore\n' >&2; return 1; }
      mh_backup_restore "${MH_RESTORE_PATH}"
      ;;
    uninstall)
      if [[ "${MH_PURGE_DATA:-0}" == "1" ]]; then mh_compose_run "${compose_dir}" down --volumes
      else mh_compose_run "${compose_dir}" down
      fi
      ;;
    *) printf 'unsupported lifecycle action for %s: %s\n' "${stack_name}" "${action}" >&2; return 1 ;;
  esac
}
