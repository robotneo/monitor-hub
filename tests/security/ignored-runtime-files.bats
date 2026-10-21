#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
  cd "${REPO_ROOT}"
}

@test "runtime environment and secret files are ignored" {
  for path in .env secrets/runtime.env runtime/state.json; do
    run git check-ignore -q "${path}"
    [ "${status}" -eq 0 ]
  done
}

@test "downloaded tools and offline package binaries are ignored" {
  for path in .tools/bats/bin/bats packages/prometheus/v1.0.0/prometheus.tar.gz; do
    run git check-ignore -q "${path}"
    [ "${status}" -eq 0 ]
  done
}
