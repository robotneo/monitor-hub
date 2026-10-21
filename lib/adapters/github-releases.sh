#!/usr/bin/env bash

if [[ -n "${MH_GITHUB_RELEASES_LOADED:-}" ]]; then
  return 0
fi
MH_GITHUB_RELEASES_LOADED=1

mh_semver_is_stable() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

mh_semver_gt() {
  local left_major left_minor left_patch
  local right_major right_minor right_patch
  IFS=. read -r left_major left_minor left_patch <<< "$1"
  IFS=. read -r right_major right_minor right_patch <<< "$2"

  if (( 10#${left_major} != 10#${right_major} )); then
    (( 10#${left_major} > 10#${right_major} ))
  elif (( 10#${left_minor} != 10#${right_minor} )); then
    (( 10#${left_minor} > 10#${right_minor} ))
  else
    (( 10#${left_patch} > 10#${right_patch} ))
  fi
}

mh_github_parse_latest_stable() {
  local releases_file="$1"
  local strip_prefix="${2:-}"
  local line tag version best=""
  local draft prerelease

  if grep -qi 'rate limit' "${releases_file}"; then
    printf 'GitHub API rate limit exceeded while resolving releases.\n' >&2
    return 1
  fi

  while IFS= read -r line; do
    if [[ "${line}" == *'"tag_name"'* ]]; then
      tag="$(printf '%s\n' "${line}" | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
    fi
    if [[ "${line}" == *'"draft"'* ]]; then
      draft="$(printf '%s\n' "${line}" | sed -E 's/.*"draft"[[:space:]]*:[[:space:]]*(true|false).*/\1/')"
    fi
    if [[ "${line}" == *'"prerelease"'* ]]; then
      prerelease="$(printf '%s\n' "${line}" | sed -E 's/.*"prerelease"[[:space:]]*:[[:space:]]*(true|false).*/\1/')"
    fi

    if [[ -n "${tag:-}" && -n "${draft:-}" && -n "${prerelease:-}" ]]; then
      if [[ "${draft}" == "false" && "${prerelease}" == "false" ]]; then
        version="${tag}"
        if [[ -n "${strip_prefix}" && "${version}" == "${strip_prefix}"* ]]; then
          version="${version#"${strip_prefix}"}"
        fi
        if mh_semver_is_stable "${version}" && \
          { [[ -z "${best}" ]] || mh_semver_gt "${version}" "${best}"; }; then
          best="${version}"
        fi
      fi
      tag=""
      draft=""
      prerelease=""
    fi
  done < "${releases_file}"

  if [[ -z "${best}" ]]; then
    printf 'no stable semantic version release found\n' >&2
    return 1
  fi
  printf '%s\n' "${best}"
}

mh_github_latest_stable() {
  local repository="$1"
  local strip_prefix="${2:-}"
  local releases_file="${MH_GITHUB_RELEASES_FILE:-}"
  local temporary_file=""
  local api_url="https://api.github.com/repos/${repository}/releases"
  local curl_bin="${MH_CURL_BIN:-curl}"
  local result

  if [[ -z "${releases_file}" ]]; then
    temporary_file="$(mktemp "${TMPDIR:-/tmp}/monitor-hub-releases.XXXXXX")"
    releases_file="${temporary_file}"
    if ! "${curl_bin}" --fail --silent --show-error --location \
      --connect-timeout 10 --max-time "${MH_NETWORK_TIMEOUT:-60}" \
      --header 'Accept: application/vnd.github+json' \
      --output "${releases_file}" "${api_url}"; then
      printf 'release lookup failed: %s\nretry: %s --fail --location %s\n' \
        "${api_url}" "${curl_bin}" "${api_url}" >&2
      rm -f "${temporary_file}"
      return 1
    fi
  fi

  if ! result="$(mh_github_parse_latest_stable "${releases_file}" "${strip_prefix}")"; then
    [[ -n "${temporary_file}" ]] && rm -f "${temporary_file}"
    return 1
  fi
  [[ -n "${temporary_file}" ]] && rm -f "${temporary_file}"
  printf '%s\n' "${result}"
}
