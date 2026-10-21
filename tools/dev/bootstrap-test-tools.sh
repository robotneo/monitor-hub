#!/usr/bin/env bash
set -euo pipefail

BATS_VERSION="1.14.0"
BATS_COMMIT="eb7f42f8d608ac693d7a4b67474f6714ea68cfc5"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
tools_dir="${repo_root}/.tools"
bats_dir="${tools_dir}/bats"

if [[ -x "${bats_dir}/bin/bats" ]]; then
  installed_version="$("${bats_dir}/bin/bats" --version)"
  installed_commit="$(git -C "${bats_dir}" rev-parse HEAD 2>/dev/null || true)"
  if [[ "${installed_version}" == "Bats ${BATS_VERSION}" && "${installed_commit}" == "${BATS_COMMIT}" ]]; then
    exit 0
  fi

  printf 'Existing Bats checkout does not match v%s at %s: %s at %s\n' \
    "${BATS_VERSION}" "${BATS_COMMIT}" "${installed_version}" "${installed_commit}" >&2
  exit 1
fi

mkdir -p "${tools_dir}"
git clone --quiet --depth 1 --branch "v${BATS_VERSION}" \
  git@github.com:bats-core/bats-core.git "${bats_dir}"

installed_commit="$(git -C "${bats_dir}" rev-parse HEAD)"
if [[ "${installed_commit}" != "${BATS_COMMIT}" ]]; then
  printf 'Bats tag resolved to unexpected commit: %s\n' "${installed_commit}" >&2
  exit 1
fi

"${bats_dir}/bin/bats" --version
