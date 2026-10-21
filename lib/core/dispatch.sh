#!/usr/bin/env bash

if [[ -n "${MH_DISPATCH_LOADED:-}" ]]; then
  return 0
fi
MH_DISPATCH_LOADED=1

mh_metadata_supports_mode() {
  local metadata_file="$1"
  local mode="$2"
  grep -Eq "^[[:space:]]+-[[:space:]]+${mode}[[:space:]]*$" "${metadata_file}"
}

mh_stack_has_profile() {
  local metadata_file="$1"
  local profile="$2"
  grep -Eq "^[[:space:]]{2}${profile}:[[:space:]]*$" "${metadata_file}"
}

mh_dispatch() {
  local kind="$1"
  local name="$2"
  local action="$3"
  local mode="$4"
  local profile="${5:-}"
  local entity_dir metadata_file hook_file hook_function

  if ! mh_valid_identifier "${name}"; then
    printf 'invalid name: %s\n' "${name}" >&2
    return 2
  fi
  case "${kind}" in
    component)
      entity_dir="${MH_COMPONENTS_DIR:-${MH_REPO_ROOT}/components}/${name}"
      metadata_file="${entity_dir}/component.yaml"
      hook_function="component_lifecycle"
      ;;
    stack)
      entity_dir="${MH_STACKS_DIR:-${MH_REPO_ROOT}/stacks}/${name}"
      metadata_file="${entity_dir}/stack.yaml"
      hook_function="stack_lifecycle"
      ;;
    *) printf 'unknown kind: %s\n' "${kind}" >&2; return 2 ;;
  esac

  if [[ ! -r "${metadata_file}" ]]; then
    printf '%s metadata is not readable: %s\n' "${kind}" "${metadata_file}" >&2
    return 1
  fi
  if ! mh_metadata_supports_mode "${metadata_file}" "${mode}"; then
    printf 'mode %s is not implemented for %s %s\n' "${mode}" "${kind}" "${name}" >&2
    return 1
  fi
  if [[ "${kind}" == "stack" ]] && ! mh_stack_has_profile "${metadata_file}" "${profile}"; then
    printf 'unknown profile for stack %s: %s\n' "${name}" "${profile}" >&2
    return 1
  fi

  hook_file="${entity_dir}/hooks/lifecycle.sh"
  if [[ ! -r "${hook_file}" ]]; then
    printf 'lifecycle hook is not readable: %s\n' "${hook_file}" >&2
    return 1
  fi
  # shellcheck disable=SC1090
  source "${hook_file}"
  if ! declare -F "${hook_function}" >/dev/null 2>&1; then
    printf 'lifecycle hook does not define %s\n' "${hook_function}" >&2
    return 1
  fi
  "${hook_function}" "${action}" "${mode}" "${profile}"
}
