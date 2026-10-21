#!/usr/bin/env bash

if [[ -n "${MH_CONTAINER_IMAGES_LOADED:-}" ]]; then
  return 0
fi
MH_CONTAINER_IMAGES_LOADED=1

mh_versions_image_repository() {
  local versions_file="$1"
  awk '
    /^images:/ { in_images = 1; next }
    in_images && /^[^[:space:]]/ { exit }
    in_images && /^[[:space:]]+repository:/ {
      sub(/^[[:space:]]+repository:[[:space:]]*/, "")
      gsub(/^['\''"]|['\''"]$/, "")
      print
      exit
    }
  ' "${versions_file}"
}

mh_resolve_image() {
  local component="$1"
  local requested_version="${2:-latest}"
  local components_dir="${MH_COMPONENTS_DIR:-}"
  local versions_file="${components_dir}/${component}/versions.yaml"
  local repository release_repository strip_prefix version reference digest
  local docker_bin="${MH_DOCKER_BIN:-docker}"

  if [[ ! -r "${versions_file}" ]]; then
    printf 'versions metadata is not readable: %s\n' "${versions_file}" >&2
    return 1
  fi
  repository="$(mh_versions_image_repository "${versions_file}")"
  if [[ -z "${repository}" ]]; then
    printf 'no container image repository configured for %s\n' "${component}" >&2
    return 1
  fi

  version="${requested_version}"
  if [[ "${version}" == "latest" || -z "${version}" ]]; then
    release_repository="$(mh_versions_top_value "${versions_file}" repository)"
    strip_prefix="$(mh_versions_strip_prefix "${versions_file}")"
    version="$(mh_github_latest_stable "${release_repository}" "${strip_prefix}")" || return 1
  fi
  reference="${repository}:${version}"

  if ! digest="$("${docker_bin}" image inspect "${reference}" \
    --format '{{index .RepoDigests 0}}' 2>/dev/null)"; then
    if ! "${docker_bin}" pull "${reference}"; then
      printf 'unable to pull image %s; configure an approved registry mirror or load it locally and retry\n' \
        "${reference}" >&2
      return 1
    fi
    digest="$("${docker_bin}" image inspect "${reference}" \
      --format '{{index .RepoDigests 0}}' 2>/dev/null)" || return 1
  fi
  if [[ -z "${digest}" ]]; then
    printf 'image has no immutable repository digest: %s\n' "${reference}" >&2
    return 1
  fi

  MH_IMAGE_REFERENCE="${reference}"
  MH_IMAGE_DIGEST="${digest}"
  export MH_IMAGE_REFERENCE MH_IMAGE_DIGEST
}
