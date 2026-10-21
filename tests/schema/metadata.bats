#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
  VALIDATOR="${REPO_ROOT}/tools/dev/validate-metadata.rb"
}

@test "valid component metadata satisfies the component contract" {
  run "${VALIDATOR}" component "${REPO_ROOT}/tests/schema/fixtures/valid-component.yaml"
  [ "$status" -eq 0 ]
}

@test "component metadata rejects missing identity support and unknown modes" {
  run "${VALIDATOR}" component "${REPO_ROOT}/tests/schema/fixtures/invalid-component.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"name"* ]]
  [[ "$output" == *"kind"* ]]
  [[ "$output" == *"support"* ]]
  [[ "$output" == *"magic-installer"* ]]
}

@test "valid stack metadata satisfies the stack contract" {
  run "${VALIDATOR}" stack "${REPO_ROOT}/tests/schema/fixtures/valid-stack.yaml"
  [ "$status" -eq 0 ]
}

@test "stack metadata rejects references to undefined profiles" {
  run "${VALIDATOR}" stack "${REPO_ROOT}/tests/schema/fixtures/invalid-stack.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing-profile"* ]]
}
