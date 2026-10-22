#!/usr/bin/env bash

if [[ -n "${MH_CONTAINER_IMAGES_LOADED:-}" ]]; then
  return 0
fi
MH_CONTAINER_IMAGES_LOADED=1

MH_CONTAINER_IMAGES_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MH_CONTAINER_IMAGES_REPO_ROOT="$(cd "${MH_CONTAINER_IMAGES_LIB_DIR}/../.." && pwd -P)"

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

mh_versions_image_tag_prefix() {
  local versions_file="$1"
  awk '
    /^images:/ { in_images = 1; next }
    in_images && /^[^[:space:]]/ { exit }
    in_images && /^[[:space:]]+tag_prefix:/ {
      sub(/^[[:space:]]+tag_prefix:[[:space:]]*/, "")
      gsub(/^['\''"]|['\''"]$/, "")
      print
      exit
    }
  ' "${versions_file}"
}

mh_local_image_latest_tag() {
  local repository="$1" docker_bin="${MH_DOCKER_BIN:-docker}"
  local tag version best_version="" best_tag=""
  while IFS= read -r tag; do
    [[ -n "${tag}" && "${tag}" != "<none>" && "${tag}" != "latest" ]] || continue
    version="${tag#v}"
    if mh_semver_is_stable "${version}" && \
      { [[ -z "${best_version}" ]] || mh_semver_gt "${version}" "${best_version}"; }; then
      best_version="${version}"
      best_tag="${tag}"
    fi
  done < <("${docker_bin}" image ls "${repository}" --format '{{.Tag}}' 2>/dev/null || true)
  [[ -n "${best_tag}" ]] || return 1
  printf '%s|%s\n' "${best_version}" "${best_tag}"
}

mh_resolve_image_reference() {
  local reference="$1" docker_bin="${MH_DOCKER_BIN:-docker}" digest
  if [[ "${reference}" == *@sha256:* ]]; then
    MH_RESOLVED_IMAGE="${reference}"
    export MH_RESOLVED_IMAGE
    return 0
  fi
  if [[ "${MH_DRY_RUN:-0}" == "1" ]]; then
    MH_RESOLVED_IMAGE="${reference}"
    export MH_RESOLVED_IMAGE
    return 0
  fi
  if ! digest="$("${docker_bin}" image inspect "${reference}" \
    --format '{{index .RepoDigests 0}}' 2>/dev/null)"; then
    if ! "${docker_bin}" pull "${reference}"; then
      printf 'unable to pull image %s; load it locally or configure an approved registry mirror and retry\n' \
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
  MH_RESOLVED_IMAGE="${digest}"
  export MH_RESOLVED_IMAGE
}

mh_resolve_image() {
  local component="$1"
  local requested_version="${2:-latest}"
  local components_dir="${MH_COMPONENTS_DIR:-${MH_CONTAINER_IMAGES_REPO_ROOT}/components}"
  local versions_file="${components_dir}/${component}/versions.yaml"
  local repository release_repository strip_prefix tag_prefix version tag reference local_match

  if [[ ! -r "${versions_file}" ]]; then
    printf 'versions metadata is not readable: %s\n' "${versions_file}" >&2
    return 1
  fi
  repository="$(mh_versions_image_repository "${versions_file}")"
  if [[ -z "${repository}" ]]; then
    printf 'no container image repository configured for %s\n' "${component}" >&2
    return 1
  fi

  tag_prefix="$(mh_versions_image_tag_prefix "${versions_file}")"
  version="${requested_version}"
  if [[ "${version}" == "latest" || -z "${version}" ]]; then
    if [[ "${MH_DRY_RUN:-0}" != "1" ]] && local_match="$(mh_local_image_latest_tag "${repository}")"; then
      version="${local_match%%|*}"
      tag="${local_match#*|}"
    else
      release_repository="$(mh_versions_top_value "${versions_file}" repository)"
      strip_prefix="$(mh_versions_strip_prefix "${versions_file}")"
      version="$(mh_github_latest_stable "${release_repository}" "${strip_prefix}")" || return 1
      tag="${tag_prefix}${version}"
    fi
  else
    version="${version#v}"
    tag="${tag_prefix}${version}"
  fi
  reference="${repository}:${tag}"

  if [[ "${MH_DRY_RUN:-0}" == "1" ]]; then
    MH_IMAGE_REFERENCE="${reference}"
    MH_IMAGE_DIGEST=""
    MH_IMAGE_VERSION="${version}"
    export MH_IMAGE_REFERENCE MH_IMAGE_DIGEST MH_IMAGE_VERSION
    return 0
  fi
  mh_resolve_image_reference "${reference}" || return 1

  MH_IMAGE_REFERENCE="${reference}"
  MH_IMAGE_DIGEST="${MH_RESOLVED_IMAGE}"
  MH_IMAGE_VERSION="${version}"
  export MH_IMAGE_REFERENCE MH_IMAGE_DIGEST MH_IMAGE_VERSION
}
