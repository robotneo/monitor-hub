#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures"
  # shellcheck source=../../lib/core/platform.sh
  source "${REPO_ROOT}/lib/core/platform.sh"
}

assert_platform() {
  local fixture="$1"
  local expected_id="$2"
  local expected_version="$3"
  MH_UNAME_MACHINE=x86_64

  mh_detect_platform "${FIXTURES}/${fixture}"

  [ "${MH_OS_ID}" = "${expected_id}" ]
  [ "${MH_OS_VERSION_ID}" = "${expected_version}" ]
  [ "${MH_ARCH}" = "amd64" ]
  [ "${MH_INIT_SYSTEM}" = "systemd" ]
}

@test "detects Ubuntu 22.04" {
  assert_platform ubuntu-22.04-os-release ubuntu 22.04
}

@test "detects Ubuntu 24.04" {
  assert_platform ubuntu-24.04-os-release ubuntu 24.04
}

@test "detects Rocky Linux 8" {
  assert_platform rocky-8-os-release rocky 8.10
}

@test "detects Rocky Linux 9" {
  assert_platform rocky-9-os-release rocky 9.5
}

@test "rejects an unsupported distribution" {
  MH_UNAME_MACHINE=x86_64

  run mh_detect_platform "${FIXTURES}/unknown-os-release"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported operating system"* ]]
}

@test "maps x86_64 to amd64" {
  MH_UNAME_MACHINE=x86_64
  mh_detect_platform "${FIXTURES}/ubuntu-22.04-os-release"

  [ "${MH_ARCH}" = "amd64" ]
}

@test "maps aarch64 to arm64" {
  MH_UNAME_MACHINE=aarch64
  mh_detect_platform "${FIXTURES}/rocky-9-os-release"

  [ "${MH_ARCH}" = "arm64" ]
}

@test "rejects an unsupported architecture" {
  MH_UNAME_MACHINE=riscv64

  run mh_detect_platform "${FIXTURES}/rocky-9-os-release"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsupported architecture"* ]]
}
