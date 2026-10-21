#!/usr/bin/env bash

if [[ -n "${MH_ARTIFACTS_LOADED:-}" ]]; then
  return 0
fi
MH_ARTIFACTS_LOADED=1

MH_ARTIFACTS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
MH_ARTIFACTS_REPO_ROOT="$(cd "${MH_ARTIFACTS_LIB_DIR}/../.." && pwd -P)"
# shellcheck source=lib/adapters/github-releases.sh disable=SC1091
source "${MH_ARTIFACTS_REPO_ROOT}/lib/adapters/github-releases.sh"
# shellcheck source=lib/adapters/container-images.sh disable=SC1091
source "${MH_ARTIFACTS_REPO_ROOT}/lib/adapters/container-images.sh"

mh_versions_top_value() {
  local versions_file="$1"
  local key="$2"
  awk -v key="${key}" '
    index($0, key ":") == 1 {
      sub("^" key ":[[:space:]]*", "")
      gsub(/^['\''"]|['\''"]$/, "")
      print
      exit
    }
  ' "${versions_file}"
}

mh_versions_strip_prefix() {
  local versions_file="$1"
  awk '
    /^tag_transform:/ { in_transform = 1; next }
    in_transform && /^[^[:space:]]/ { exit }
    in_transform && /^[[:space:]]+strip_prefix:/ {
      sub(/^[[:space:]]+strip_prefix:[[:space:]]*/, "")
      gsub(/^['\''"]|['\''"]$/, "")
      print
      exit
    }
  ' "${versions_file}"
}

mh_versions_artifact_record() {
  local versions_file="$1"
  local requested_os="$2"
  local requested_arch="$3"
  awk -v wanted_os="${requested_os}" -v wanted_arch="${requested_arch}" '
    function trim_value() {
      sub(/^[^:]+:[[:space:]]*/, "")
      gsub(/^['\''"]|['\''"]$/, "")
    }
    function emit() {
      if (item_os == wanted_os && item_arch == wanted_arch && filename != "") {
        print filename "|" checksum
        found = 1
      }
    }
    /^artifacts:/ { in_artifacts = 1; next }
    in_artifacts && /^[^[:space:]]/ { emit(); exit }
    in_artifacts && /^[[:space:]]+- os:/ {
      emit()
      item_os = $0; trim_value()
      item_os = $0; item_arch = ""; filename = ""; checksum = ""
      next
    }
    in_artifacts && /^[[:space:]]+architecture:/ { item_arch = $0; trim_value(); item_arch = $0; next }
    in_artifacts && /^[[:space:]]+filename:/ { filename = $0; trim_value(); filename = $0; next }
    in_artifacts && /^[[:space:]]+checksum:/ { checksum = $0; trim_value(); checksum = $0; next }
    END { if (!found) emit() }
  ' "${versions_file}"
}

mh_render_artifact_filename() {
  local template="$1"
  local version="$2"
  local os="$3"
  local arch="$4"
  template="${template//\{version\}/${version}}"
  template="${template//\{os\}/${os}}"
  template="${template//\{architecture\}/${arch}}"
  printf '%s\n' "${template}"
}

mh_sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

mh_verify_artifact() {
  local path="$1"
  local expected="${2#sha256:}"
  local actual
  actual="$(mh_sha256_file "${path}")"
  if [[ -n "${expected}" && "${actual}" != "${expected}" ]]; then
    printf 'checksum mismatch for %s: expected %s, got %s\n' \
      "${path}" "${expected}" "${actual}" >&2
    return 1
  fi
  MH_ARTIFACT_SHA256="sha256:${actual}"
}

mh_artifact_version_from_name() {
  local filename="$1"
  local template="$2"
  local os="$3"
  local arch="$4"
  local prefix="${template%%\{version\}*}"
  local suffix="${template#*\{version\}}"
  prefix="$(mh_render_artifact_filename "${prefix}" '' "${os}" "${arch}")"
  suffix="$(mh_render_artifact_filename "${suffix}" '' "${os}" "${arch}")"
  filename="${filename#"${prefix}"}"
  filename="${filename%"${suffix}"}"
  printf '%s\n' "${filename}"
}

mh_find_best_local_artifact() {
  local directory="$1"
  local template="$2"
  local os="$3"
  local arch="$4"
  local pattern path filename version best_version="" best_path=""
  pattern="$(mh_render_artifact_filename "${template}" '*' "${os}" "${arch}")"

  [[ -d "${directory}" ]] || return 1
  while IFS= read -r path; do
    filename="${path##*/}"
    version="$(mh_artifact_version_from_name "${filename}" "${template}" "${os}" "${arch}")"
    if mh_semver_is_stable "${version}" && \
      { [[ -z "${best_version}" ]] || mh_semver_gt "${version}" "${best_version}"; }; then
      best_version="${version}"
      best_path="${path}"
    fi
  done < <(find "${directory}" -maxdepth 1 -type f -name "${pattern}" -print 2>/dev/null)

  [[ -n "${best_path}" ]] || return 1
  printf '%s|%s\n' "${best_version}" "${best_path}"
}

mh_accept_artifact() {
  local version="$1"
  local path="$2"
  local source="$3"
  local expected_checksum="$4"
  mh_verify_artifact "${path}" "${expected_checksum}" || return 1
  MH_ARTIFACT_VERSION="${version}"
  MH_ARTIFACT_PATH="${path}"
  MH_ARTIFACT_SOURCE="${source}"
  export MH_ARTIFACT_VERSION MH_ARTIFACT_PATH MH_ARTIFACT_SOURCE MH_ARTIFACT_SHA256
}

mh_resolve_artifact() {
  local component="$1"
  local requested_version="${2:-latest}"
  local os="$3"
  local arch="$4"
  local components_dir="${MH_COMPONENTS_DIR:-${MH_ARTIFACTS_REPO_ROOT}/components}"
  local packages_dir="${MH_PACKAGES_DIR:-${MH_ARTIFACTS_REPO_ROOT}/packages}"
  local cache_dir="${MH_CACHE_DIR:-/var/cache/monitor-hub}"
  local versions_file="${components_dir}/${component}/versions.yaml"
  local record template checksum filename path match version repository strip_prefix tag url
  local cache_artifacts_dir="${cache_dir}/artifacts"
  local temporary_path

  if [[ ! -r "${versions_file}" ]]; then
    printf 'versions metadata is not readable: %s\n' "${versions_file}" >&2
    return 1
  fi
  record="$(mh_versions_artifact_record "${versions_file}" "${os}" "${arch}")"
  if [[ -z "${record}" ]]; then
    printf 'no compatible artifact for %s on %s/%s\n' "${component}" "${os}" "${arch}" >&2
    return 1
  fi
  template="${record%%|*}"
  checksum="${record#*|}"

  if [[ "${requested_version}" != "latest" && -n "${requested_version}" ]]; then
    version="${requested_version}"
    filename="$(mh_render_artifact_filename "${template}" "${version}" "${os}" "${arch}")"
    path="${packages_dir}/${filename}"
    [[ -f "${path}" ]] && mh_accept_artifact "${version}" "${path}" packages "${checksum}" && return 0
    path="${cache_artifacts_dir}/${filename}"
    [[ -f "${path}" ]] && mh_accept_artifact "${version}" "${path}" cache "${checksum}" && return 0
  else
    if match="$(mh_find_best_local_artifact "${packages_dir}" "${template}" "${os}" "${arch}")"; then
      version="${match%%|*}"
      path="${match#*|}"
      mh_accept_artifact "${version}" "${path}" packages "${checksum}" && return 0
      return 1
    fi
    if match="$(mh_find_best_local_artifact "${cache_artifacts_dir}" "${template}" "${os}" "${arch}")"; then
      version="${match%%|*}"
      path="${match#*|}"
      mh_accept_artifact "${version}" "${path}" cache "${checksum}" && return 0
      return 1
    fi
    repository="$(mh_versions_top_value "${versions_file}" repository)"
    strip_prefix="$(mh_versions_strip_prefix "${versions_file}")"
    version="$(mh_github_latest_stable "${repository}" "${strip_prefix}")" || return 1
  fi

  repository="$(mh_versions_top_value "${versions_file}" repository)"
  strip_prefix="$(mh_versions_strip_prefix "${versions_file}")"
  tag="${strip_prefix}${version}"
  filename="$(mh_render_artifact_filename "${template}" "${version}" "${os}" "${arch}")"
  url="https://github.com/${repository}/releases/download/${tag}/${filename}"
  mkdir -p "${cache_artifacts_dir}"
  path="${cache_artifacts_dir}/${filename}"
  temporary_path="${path}.tmp.$$"

  if [[ -n "${MH_DOWNLOAD_SOURCE_DIR:-}" && -f "${MH_DOWNLOAD_SOURCE_DIR}/${filename}" ]]; then
    cp "${MH_DOWNLOAD_SOURCE_DIR}/${filename}" "${temporary_path}"
  elif ! "${MH_CURL_BIN:-curl}" --fail --location --show-error \
    --connect-timeout 10 --max-time "${MH_NETWORK_TIMEOUT:-120}" \
    --output "${temporary_path}" "${url}"; then
    rm -f "${temporary_path}"
    printf 'artifact download failed: %s\nrequired file: %s\nplace it in: %s\nexpected checksum: %s\nretry: monitorctl component %s install --version %s\n' \
      "${url}" "${filename}" "${packages_dir}" "${checksum:-unknown}" "${component}" "${version}" >&2
    return 1
  fi

  if ! mh_verify_artifact "${temporary_path}" "${checksum}"; then
    rm -f "${temporary_path}"
    return 1
  fi
  mv "${temporary_path}" "${path}"
  MH_ARTIFACT_VERSION="${version}"
  MH_ARTIFACT_PATH="${path}"
  MH_ARTIFACT_SOURCE="network"
  export MH_ARTIFACT_VERSION MH_ARTIFACT_PATH MH_ARTIFACT_SOURCE MH_ARTIFACT_SHA256
}
