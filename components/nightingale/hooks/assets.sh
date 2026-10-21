#!/usr/bin/env bash

if [[ -n "${MH_NIGHTINGALE_ASSETS_LOADED:-}" ]]; then
  return 0
fi
MH_NIGHTINGALE_ASSETS_LOADED=1

nightingale_download_asset() {
  local url="$1"
  local destination="$2"
  local temporary_path="${destination}.tmp.$$"

  if ! "${MH_CURL_BIN:-curl}" --fail --location --show-error \
    --connect-timeout 10 --max-time "${MH_NETWORK_TIMEOUT:-120}" \
    --output "${temporary_path}" "${url}"; then
    rm -f "${temporary_path}"
    printf 'Nightingale asset download failed: %s\nnetwork may be unavailable or GitHub may be slow; place the exact-version file in packages/ and retry\n' \
      "${url}" >&2
    return 1
  fi

  mv "${temporary_path}" "${destination}"
}

nightingale_prepare_release_assets() {
  local version="$1"
  local target_dir="$2"
  local component_dir repo_root packages_dir source_dir
  local sql_package config_package
  local sql_target="${target_dir}/n9e.sql"
  local config_target="${target_dir}/config.toml.upstream"
  local base_url

  if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    printf 'Nightingale assets require an exact version, got: %s\n' "${version}" >&2
    return 1
  fi

  component_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
  repo_root="$(cd "${component_dir}/../.." && pwd -P)"
  packages_dir="${MH_PACKAGES_DIR:-${repo_root}/packages}"
  source_dir="${MH_NIGHTINGALE_ASSET_SOURCE_DIR:-}"
  sql_package="${packages_dir}/nightingale-${version}-n9e.sql"
  config_package="${packages_dir}/nightingale-${version}-config.toml"
  base_url="https://raw.githubusercontent.com/ccfos/nightingale/v${version}"

  mkdir -p "${target_dir}"

  if [[ -n "${source_dir}" ]]; then
    if [[ ! -f "${source_dir}/n9e.sql" || ! -f "${source_dir}/config.toml" ]]; then
      printf 'offline Nightingale asset directory must contain n9e.sql and config.toml: %s\n' \
        "${source_dir}" >&2
      return 1
    fi
    cp "${source_dir}/n9e.sql" "${sql_target}"
    cp "${source_dir}/config.toml" "${config_target}"
    return 0
  fi

  if [[ -f "${sql_package}" ]]; then
    cp "${sql_package}" "${sql_target}"
  else
    nightingale_download_asset \
      "${base_url}/docker/initsql/a-n9e.sql" "${sql_target}" || return 1
  fi

  if [[ -f "${config_package}" ]]; then
    cp "${config_package}" "${config_target}"
  else
    nightingale_download_asset \
      "${base_url}/etc/config.toml" "${config_target}" || return 1
  fi
}
