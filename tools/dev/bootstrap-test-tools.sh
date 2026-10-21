#!/usr/bin/env bash
set -euo pipefail

BATS_VERSION="1.14.0"
BATS_COMMIT="eb7f42f8d608ac693d7a4b67474f6714ea68cfc5"
JSON_SCHEMER_VERSION="2.2.1"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
tools_dir="${repo_root}/.tools"
bats_dir="${tools_dir}/bats"
ruby_dir="${tools_dir}/ruby"
gem_cache_dir="${tools_dir}/gem-cache"

if [[ -x "${bats_dir}/bin/bats" ]]; then
  installed_version="$("${bats_dir}/bin/bats" --version)"
  installed_commit="$(git -C "${bats_dir}" rev-parse HEAD 2>/dev/null || true)"
  if [[ "${installed_version}" == "Bats ${BATS_VERSION}" && "${installed_commit}" == "${BATS_COMMIT}" ]]; then
    :
  else
    printf 'Existing Bats checkout does not match v%s at %s: %s at %s\n' \
      "${BATS_VERSION}" "${BATS_COMMIT}" "${installed_version}" "${installed_commit}" >&2
    exit 1
  fi
else
  mkdir -p "${tools_dir}"
  git clone --quiet --depth 1 --branch "v${BATS_VERSION}" \
    git@github.com:bats-core/bats-core.git "${bats_dir}"

  installed_commit="$(git -C "${bats_dir}" rev-parse HEAD)"
  if [[ "${installed_commit}" != "${BATS_COMMIT}" ]]; then
    printf 'Bats tag resolved to unexpected commit: %s\n' "${installed_commit}" >&2
    exit 1
  fi
fi

"${bats_dir}/bin/bats" --version

system_gem_path="$(ruby -e 'print Gem.path.join(":")')"
if GEM_HOME="${ruby_dir}" GEM_PATH="${ruby_dir}:${system_gem_path}" ruby -e \
  "gem 'json_schemer', '=${JSON_SCHEMER_VERSION}'; require 'json_schemer'" 2>/dev/null; then
  exit 0
fi

mkdir -p "${ruby_dir}" "${gem_cache_dir}"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

install_pinned_gem() {
  local name="$1"
  local version="$2"
  local expected_sha256="$3"
  local gem_file="${gem_cache_dir}/${name}-${version}.gem"
  local actual_sha256

  if [[ ! -f "${gem_file}" ]]; then
    if ! curl --fail --location --silent --show-error \
      --connect-timeout 10 --max-time 120 \
      --output "${gem_file}" \
      "https://rubygems.org/downloads/${name}-${version}.gem"; then
      printf 'Unable to download %s %s. Check the network or place the gem at %s and retry.\n' \
        "${name}" "${version}" "${gem_file}" >&2
      return 1
    fi
  fi

  actual_sha256="$(sha256_file "${gem_file}")"
  if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
    printf 'Checksum mismatch for %s: expected %s, got %s\n' \
      "${gem_file}" "${expected_sha256}" "${actual_sha256}" >&2
    return 1
  fi

  gem install --local --ignore-dependencies --install-dir "${ruby_dir}" \
    --no-document "${gem_file}"
}

install_pinned_gem base64 0.3.0 \
  27337aeabad6ffae05c265c450490628ef3ebd4b67be58257393227588f5a97b
install_pinned_gem hana 1.3.7 \
  5425db42d651fea08859811c29d20446f16af196308162894db208cac5ce9b0d
install_pinned_gem regexp_parser 2.13.1 \
  5aedb6b7c35688f51e86eef17a15374dfd287c83f4ca644b2c5f3ec50a33b44b
install_pinned_gem simpleidn 0.2.3 \
  08ce96f03fa1605286be22651ba0fc9c0b2d6272c9b27a260bc88be05b0d2c29
install_pinned_gem json_schemer "${JSON_SCHEMER_VERSION}" \
  953c2766da233a978d136b03cd14ac40cfa280219dd874998c184d6e02fce73e
