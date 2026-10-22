#!/usr/bin/env bash
set -euo pipefail

BATS_VERSION="1.14.0"
BATS_COMMIT="eb7f42f8d608ac693d7a4b67474f6714ea68cfc5"
JSON_SCHEMER_VERSION="2.2.1"
SHELLCHECK_VERSION="0.11.0"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
tools_dir="${repo_root}/.tools"
bats_dir="${tools_dir}/bats"
ruby_dir="${tools_dir}/ruby"
gem_cache_dir="${tools_dir}/gem-cache"
shellcheck_cache_dir="${tools_dir}/shellcheck-cache"
shellcheck_dir="${tools_dir}/shellcheck-v${SHELLCHECK_VERSION}"
shellcheck_bin="${shellcheck_dir}/shellcheck"

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
    https://github.com/bats-core/bats-core.git "${bats_dir}"

  installed_commit="$(git -C "${bats_dir}" rev-parse HEAD)"
  if [[ "${installed_commit}" != "${BATS_COMMIT}" ]]; then
    printf 'Bats tag resolved to unexpected commit: %s\n' "${installed_commit}" >&2
    exit 1
  fi
fi

"${bats_dir}/bin/bats" --version

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

system_gem_path="$(ruby -e 'print Gem.path.join(":")')"
if ! GEM_HOME="${ruby_dir}" GEM_PATH="${ruby_dir}:${system_gem_path}" ruby -e \
  "gem 'json_schemer', '=${JSON_SCHEMER_VERSION}'; require 'json_schemer'" 2>/dev/null; then
  mkdir -p "${ruby_dir}" "${gem_cache_dir}"

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
fi

if [[ -x "${shellcheck_bin}" ]] && \
  "${shellcheck_bin}" --version | grep -q "version: ${SHELLCHECK_VERSION}"; then
  exit 0
fi

case "$(uname -s):$(uname -m)" in
  Darwin:x86_64)
    shellcheck_platform="darwin.x86_64"
    shellcheck_sha256="c2c15e08df0e8fbc374c335b230a7ee958c313fa5714817a59aa59f1aa594f51"
    ;;
  Darwin:arm64 | Darwin:aarch64)
    shellcheck_platform="darwin.aarch64"
    shellcheck_sha256="339b930feb1ea764467013cc1f72d09cd6b869ebf1013296ba9055ab2ffbd26f"
    ;;
  Linux:x86_64)
    shellcheck_platform="linux.x86_64"
    shellcheck_sha256="b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6"
    ;;
  Linux:arm64 | Linux:aarch64)
    shellcheck_platform="linux.aarch64"
    shellcheck_sha256="68a8133197a50beb8803f8d42f9908d1af1c5540d4bb05fdfca8c1fa47decefc"
    ;;
  *)
    printf 'No pinned ShellCheck binary for %s %s.\n' "$(uname -s)" "$(uname -m)" >&2
    exit 1
    ;;
esac

mkdir -p "${shellcheck_cache_dir}"
shellcheck_archive="${shellcheck_cache_dir}/shellcheck-v${SHELLCHECK_VERSION}.${shellcheck_platform}.tar.gz"
if [[ ! -f "${shellcheck_archive}" ]] || \
  [[ "$(sha256_file "${shellcheck_archive}")" != "${shellcheck_sha256}" ]]; then
  if ! curl --fail --location --silent --show-error --http1.1 --continue-at - \
    --connect-timeout 10 --max-time 120 \
    --output "${shellcheck_archive}" \
    "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/$(basename "${shellcheck_archive}")"; then
    printf 'Unable to download ShellCheck. Check the network or place the archive at %s and retry.\n' \
      "${shellcheck_archive}" >&2
    exit 1
  fi
fi

shellcheck_actual_sha256="$(sha256_file "${shellcheck_archive}")"
if [[ "${shellcheck_actual_sha256}" != "${shellcheck_sha256}" ]]; then
  printf 'Checksum mismatch for %s: expected %s, got %s\n' \
    "${shellcheck_archive}" "${shellcheck_sha256}" "${shellcheck_actual_sha256}" >&2
  exit 1
fi

tar -xzf "${shellcheck_archive}" -C "${tools_dir}"
"${shellcheck_bin}" --version
