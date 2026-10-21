#!/usr/bin/env bash

if [[ -n "${MH_LOG_LOADED:-}" ]]; then
  return 0
fi
MH_LOG_LOADED=1

MH_LOG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/core/constants.sh disable=SC1091
source "${MH_LOG_LIB_DIR}/constants.sh"

MH_REGISTERED_SECRETS=()

mh_register_secret() {
  local secret="${1:-}"
  if [[ -n "${secret}" ]]; then
    MH_REGISTERED_SECRETS+=("${secret}")
  fi
}

mh_log_level_rank() {
  case "$1" in
    debug) printf '%s\n' 10 ;;
    info) printf '%s\n' 20 ;;
    warn) printf '%s\n' 30 ;;
    error) printf '%s\n' 40 ;;
    *) return 1 ;;
  esac
}

mh_redact() {
  local message="$1"
  local secret
  for secret in "${MH_REGISTERED_SECRETS[@]}"; do
    message="${message//"${secret}"/[REDACTED]}"
  done
  printf '%s\n' "${message}"
}

mh_log() {
  local level="${1:-}"
  shift || true
  local configured_level="${MH_LOG_LEVEL:-${MH_DEFAULT_LOG_LEVEL}}"
  local level_rank
  local configured_rank
  local message

  if ! level_rank="$(mh_log_level_rank "${level}")"; then
    printf 'unknown log level: %s\n' "${level}" >&2
    return 2
  fi
  if ! configured_rank="$(mh_log_level_rank "${configured_level}")"; then
    printf 'unknown configured log level: %s\n' "${configured_level}" >&2
    return 2
  fi
  if (( level_rank < configured_rank )); then
    return 0
  fi

  message="$(mh_redact "$*")"
  printf '%s [%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "${level}" "${message}"
}
