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
# shellcheck source=lib/core/runtime-paths.sh disable=SC1091
source "${MH_STACK_COMPOSE_REPO_ROOT}/lib/core/runtime-paths.sh"

mh_stack_image_is_pinned() {
  local value="$1"
  [[ -n "${value}" && "${value}" != *:latest && \
    ( "${value}" == *@sha256:* || "${value##*/}" == *:* ) ]]
}

mh_stack_requested_version() {
  local component="$1" spec="${MH_VERSION:-latest}" entry key value
  local -a entries=()
  MH_STACK_REQUESTED_VERSION=latest
  if [[ "${spec}" == "latest" || -z "${spec}" ]]; then
    export MH_STACK_REQUESTED_VERSION
    return 0
  fi
  if [[ "${spec}" != *=* ]]; then
    printf 'stack --version must be a comma-separated component=version map, got: %s\n' \
      "${spec}" >&2
    return 1
  fi
  IFS=',' read -r -a entries <<< "${spec}"
  for entry in "${entries[@]}"; do
    key="${entry%%=*}"
    value="${entry#*=}"
    if [[ "${key}" == "${entry}" || ! "${key}" =~ ^[a-z0-9][a-z0-9-]*$ || \
      -z "${value}" || "${value}" == *=* ]]; then
      printf 'invalid stack version entry: %s (expected component=version)\n' "${entry}" >&2
      return 1
    fi
    if [[ "${key}" == "${component}" ]]; then
      if [[ "${MH_STACK_REQUESTED_VERSION}" != "latest" ]]; then
        printf 'duplicate stack version entry for component: %s\n' "${component}" >&2
        return 1
      fi
      MH_STACK_REQUESTED_VERSION="${value}"
    fi
  done
  MH_STACK_VERSION_KEYS_SEEN="${MH_STACK_VERSION_KEYS_SEEN}${component},"
  export MH_STACK_REQUESTED_VERSION MH_STACK_VERSION_KEYS_SEEN
}

mh_stack_validate_version_map() {
  local spec="${MH_VERSION:-latest}" entry key
  local -a entries=()
  [[ "${spec}" == "latest" || -z "${spec}" ]] && return 0
  IFS=',' read -r -a entries <<< "${spec}"
  for entry in "${entries[@]}"; do
    key="${entry%%=*}"
    if [[ "${MH_STACK_VERSION_KEYS_SEEN}" != *",${key},"* ]]; then
      printf 'stack version map references a component not used by this stack: %s\n' "${key}" >&2
      return 1
    fi
  done
}

mh_stack_validate_requested_version_keys() {
  local metadata_file="$1" spec="${MH_VERSION:-latest}" entry key component
  local allowed=','
  local -a entries=()
  [[ "${spec}" == "latest" || -z "${spec}" ]] && return 0
  while IFS= read -r component; do
    allowed="${allowed}${component},"
  done < <(awk '
    /^components:/ { in_components = 1; next }
    in_components && /^[^[:space:]]/ { exit }
    in_components && /^[[:space:]]*-[[:space:]]*name:/ {
      sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/, "")
      gsub(/^['\''"]|['\''"]$/, "")
      print
    }
  ' "${metadata_file}")
  IFS=',' read -r -a entries <<< "${spec}"
  for entry in "${entries[@]}"; do
    key="${entry%%=*}"
    if [[ "${allowed}" != *",${key},"* ]]; then
      printf 'stack version map references a component not used by this stack: %s\n' "${key}" >&2
      return 1
    fi
  done
}

mh_stack_require_component_image() {
  local component="$1" variable="$2" value requested_version
  MH_STACK_IMAGE_VARIABLES+=("${variable}")
  mh_stack_requested_version "${component}" || return 1
  requested_version="${MH_STACK_REQUESTED_VERSION}"
  value="${!variable:-}"
  if [[ -n "${value}" ]]; then
    if [[ "${requested_version}" != "latest" ]]; then
      printf '%s is set explicitly and also appears in --version; choose one source\n' \
        "${variable}" >&2
      return 1
    fi
    if ! mh_stack_image_is_pinned "${value}"; then
      printf '%s must use an exact tag or immutable digest, got: %s\n' "${variable}" "${value}" >&2
      return 1
    fi
    mh_resolve_image_reference "${value}" || return 1
    printf -v "${variable}" '%s' "${MH_RESOLVED_IMAGE}"
    export "${variable?}"
    if [[ "${component}" == "nightingale" && -z "${NIGHTINGALE_VERSION:-}" && "${value}" != *@sha256:* ]]; then
      NIGHTINGALE_VERSION="${value##*:}"
      NIGHTINGALE_VERSION="${NIGHTINGALE_VERSION#v}"
      export NIGHTINGALE_VERSION
    fi
    return 0
  fi
  mh_resolve_image "${component}" "${requested_version}" || return 1
  printf -v "${variable}" '%s' "${MH_IMAGE_DIGEST:-${MH_IMAGE_REFERENCE}}"
  export "${variable?}"
  if [[ "${component}" == "nightingale" ]]; then
    NIGHTINGALE_VERSION="${MH_IMAGE_VERSION}"
    export NIGHTINGALE_VERSION
  fi
}

mh_stack_require_external_image() {
  local default_reference="$1" variable="$2" value digest
  local docker_bin="${MH_DOCKER_BIN:-docker}"
  MH_STACK_IMAGE_VARIABLES+=("${variable}")
  value="${!variable:-${default_reference}}"
  if ! mh_stack_image_is_pinned "${value}"; then
    printf '%s must use an exact tag or immutable digest, got: %s\n' "${variable}" "${value}" >&2
    return 1
  fi
  if [[ "${value}" == *@sha256:* ]]; then
    printf -v "${variable}" '%s' "${value}"
    export "${variable?}"
    return 0
  fi
  if [[ "${MH_DRY_RUN:-0}" == "1" ]]; then
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
  local path="$1" uid="${2:-0}" gid="${3:-0}"
  mkdir -p "$(dirname "${path}")"
  if [[ ! -e "${path}" ]]; then
    command -v openssl >/dev/null 2>&1 || { printf 'openssl is required to generate runtime secrets\n' >&2; return 1; }
    (umask 077; openssl rand -hex 24 > "${path}")
  fi
  mh_secure_service_file "${path}" "${uid}" "${gid}" 0400
}

# shellcheck source=lib/core/stack-runtime.sh disable=SC1091
source "${MH_STACK_COMPOSE_REPO_ROOT}/lib/core/stack-runtime.sh"
