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
