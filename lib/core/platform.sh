#!/usr/bin/env bash

if [[ -n "${MH_PLATFORM_LOADED:-}" ]]; then
  return 0
fi
MH_PLATFORM_LOADED=1

mh_os_release_value() {
  local path="$1"
  local requested_key="$2"
  local key
  local value

  while IFS='=' read -r key value; do
    if [[ "${key}" == "${requested_key}" ]]; then
      value="${value#\"}"
      value="${value%\"}"
      value="${value#\'}"
      value="${value%\'}"
      printf '%s\n' "${value}"
      return 0
    fi
  done < "${path}"
  return 1
}

mh_detect_platform() {
  local os_release_path="${1:-/etc/os-release}"
  local machine

  if [[ ! -r "${os_release_path}" ]]; then
    printf 'operating system metadata is not readable: %s\n' "${os_release_path}" >&2
    return 1
  fi

  MH_OS_ID="$(mh_os_release_value "${os_release_path}" ID || true)"
  MH_OS_VERSION_ID="$(mh_os_release_value "${os_release_path}" VERSION_ID || true)"

  case "${MH_OS_ID}:${MH_OS_VERSION_ID}" in
    ubuntu:22.04 | ubuntu:24.04 | rocky:8 | rocky:8.* | rocky:9 | rocky:9.*) ;;
    *)
      printf 'unsupported operating system: %s %s\n' \
        "${MH_OS_ID:-unknown}" "${MH_OS_VERSION_ID:-unknown}" >&2
      return 1
      ;;
  esac

  machine="${MH_UNAME_MACHINE:-$(uname -m)}"
  case "${machine}" in
    x86_64 | amd64) MH_ARCH="amd64" ;;
    aarch64 | arm64) MH_ARCH="arm64" ;;
    *)
      printf 'unsupported architecture: %s\n' "${machine}" >&2
      return 1
      ;;
  esac

  MH_INIT_SYSTEM="systemd"
  export MH_OS_ID MH_OS_VERSION_ID MH_ARCH MH_INIT_SYSTEM
}
