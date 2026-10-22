#!/usr/bin/env bash

if [[ -n "${MH_STATE_LOADED:-}" ]]; then
  return 0
fi
MH_STATE_LOADED=1

mh_state_validate_identifier() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

mh_state_path() {
  local kind="$1"
  local name="$2"
  local state_dir="${MH_STATE_DIR:-/var/lib/monitor-hub}"
  if ! mh_state_validate_identifier "${kind}" || ! mh_state_validate_identifier "${name}"; then
    printf 'invalid state identifier: %s/%s\n' "${kind}" "${name}" >&2
    return 1
  fi
  printf '%s/%s/%s.json\n' "${state_dir}" "${kind}" "${name}"
}

mh_state_read() {
  local path
  path="$(mh_state_path "$1" "$2")" || return 1
  if [[ ! -r "${path}" ]]; then
    printf 'state file is not readable: %s\n' "${path}" >&2
    return 1
  fi
  cat "${path}"
}

mh_state_write() {
  local kind="$1"
  local name="$2"
  local json_file="$3"
  local path temporary_path

  path="$(mh_state_path "${kind}" "${name}")" || return 1
  if [[ ! -r "${json_file}" ]]; then
    printf 'state input is not readable: %s\n' "${json_file}" >&2
    return 1
  fi

  mkdir -p "$(dirname "${path}")"
  temporary_path="${path}.tmp.$$"
  if ! cp "${json_file}" "${temporary_path}"; then
    rm -f "${temporary_path}"
    return 1
  fi
  chmod 0600 "${temporary_path}"
  mv "${temporary_path}" "${path}"
}

mh_state_images_path() {
  local kind="$1" name="$2" state_dir="${MH_STATE_DIR:-/var/lib/monitor-hub}"
  if ! mh_state_validate_identifier "${kind}" || ! mh_state_validate_identifier "${name}"; then
    printf 'invalid state identifier: %s/%s\n' "${kind}" "${name}" >&2
    return 1
  fi
  printf '%s/%s/%s.images.tsv\n' "${state_dir}" "${kind}" "${name}"
}

mh_state_write_images() {
  local kind="$1" name="$2"
  shift 2
  local path temporary_path variable value
  path="$(mh_state_images_path "${kind}" "${name}")" || return 1
  mkdir -p "$(dirname "${path}")"
  temporary_path="${path}.tmp.$$"
  : > "${temporary_path}"
  for variable in "$@"; do
    if [[ ! "${variable}" =~ ^[A-Z][A-Z0-9_]*_IMAGE$ ]]; then
      printf 'invalid image variable in state: %s\n' "${variable}" >&2
      rm -f "${temporary_path}"
      return 1
    fi
    value="${!variable:-}"
    if [[ "${value}" != *@sha256:* ]]; then
      printf 'image state must use an immutable digest: %s\n' "${variable}" >&2
      rm -f "${temporary_path}"
      return 1
    fi
    printf '%s\t%s\n' "${variable}" "${value}" >> "${temporary_path}"
  done
  chmod 0600 "${temporary_path}"
  mv "${temporary_path}" "${path}"
}

mh_state_restore_images() {
  local kind="$1" name="$2" path variable value
  path="$(mh_state_images_path "${kind}" "${name}")" || return 1
  [[ -r "${path}" ]] || return 1
  while IFS=$'\t' read -r variable value; do
    if [[ ! "${variable}" =~ ^[A-Z][A-Z0-9_]*_IMAGE$ || "${value}" != *@sha256:* ]]; then
      printf 'invalid image state entry: %s\n' "${variable}" >&2
      return 1
    fi
    printf -v "${variable}" '%s' "${value}"
    export "${variable?}"
  done < "${path}"
}
