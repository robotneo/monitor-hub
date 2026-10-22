#!/usr/bin/env bash

if [[ -n "${MH_RUNTIME_PATHS_LOADED:-}" ]]; then
  return 0
fi
MH_RUNTIME_PATHS_LOADED=1

mh_path_is_safe_child() {
  local target="$1" parent="$2"
  [[ -n "${target}" && -n "${parent}" && "${target}" == /* && "${parent}" == /* ]] || return 1
  [[ "${target}" != *'/../'* && "${target}" != *'/./'* && "${target}" != */.. && "${target}" != */. ]] || return 1
  [[ "${target}" == "${parent}/"* && "${target}" != "${parent}" && "${target}" != "${parent}/" ]]
}

mh_purge_managed_path() {
  local target="$1" managed_root="$2"
  if ! mh_path_is_safe_child "${target}" "${managed_root}"; then
    printf 'refusing to purge unsafe path: %s (managed root: %s)\n' "${target}" "${managed_root}" >&2
    return 1
  fi
  if [[ "${MH_ASSUME_YES:-0}" != "1" ]]; then
    printf 'permanent deletion requires --purge-data --yes: %s\n' "${target}" >&2
    return 1
  fi
  rm -rf -- "${target}"
}

mh_ownership_current_uid() {
  id -u
}

mh_apply_service_ownership() {
  local path="$1" uid="$2" gid="$3" mode="$4"
  local chown_bin="${MH_CHOWN_BIN:-chown}"
  local chmod_bin="${MH_CHMOD_BIN:-chmod}"

  "${chmod_bin}" "${mode}" "${path}" || return 1
  if [[ "${MH_SKIP_OWNERSHIP:-0}" == "1" ]]; then
    return 0
  fi
  if [[ "${MH_FORCE_OWNERSHIP:-0}" == "1" || "$(mh_ownership_current_uid)" == "0" ]]; then
    "${chown_bin}" "${uid}:${gid}" "${path}"
    return $?
  fi
  printf 'root privileges are required to set %s ownership to %s:%s\n' "${path}" "${uid}" "${gid}" >&2
  return 1
}

mh_ensure_service_directory() {
  local path="$1" uid="$2" gid="$3" mode="${4:-0750}"
  mkdir -p "${path}" || return 1
  mh_apply_service_ownership "${path}" "${uid}" "${gid}" "${mode}"
}

mh_secure_service_file() {
  local path="$1" uid="$2" gid="$3" mode="${4:-0400}"
  [[ -f "${path}" && ! -L "${path}" ]] || {
    printf 'service secret is not a regular file: %s\n' "${path}" >&2
    return 1
  }
  mh_apply_service_ownership "${path}" "${uid}" "${gid}" "${mode}"
}
