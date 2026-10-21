#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
  VALIDATOR="${REPO_ROOT}/tools/dev/validate-metadata.rb"
  COMPONENTS=(victoriametrics vmagent vmalert nightingale categraf)
}

@test "new components satisfy component and version contracts" {
  local component
  for component in "${COMPONENTS[@]}"; do
    run "${VALIDATOR}" component "${REPO_ROOT}/components/${component}/component.yaml"
    [ "$status" -eq 0 ]
    run "${VALIDATOR}" versions "${REPO_ROOT}/components/${component}/versions.yaml"
    [ "$status" -eq 0 ]
  done
}

@test "new components declare service ports and health checks" {
  local component metadata
  for component in "${COMPONENTS[@]}"; do
    metadata="${REPO_ROOT}/components/${component}/component.yaml"
    run grep -E 'port:[[:space:]]+[0-9]+' "${metadata}"
    [ "$status" -eq 0 ]
    run grep -E 'target:[[:space:]]+.+$' "${metadata}"
    [ "$status" -eq 0 ]
  done
}

@test "VictoriaMetrics write and alert connections are explicit" {
  run grep -R -F '/api/v1/write' \
    "${REPO_ROOT}/components/vmagent" "${REPO_ROOT}/components/vmalert" "${REPO_ROOT}/components/categraf"
  [ "$status" -eq 0 ]
  run grep -R -F 'alertmanager:9093' "${REPO_ROOT}/components/vmalert"
  [ "$status" -eq 0 ]
}

@test "new component configuration contains no fixed credentials or latest images" {
  run grep -R -nE '(password|secret|dsn)[[:space:]]*[:=][[:space:]]+[A-Za-z0-9]' \
    "${REPO_ROOT}/components/victoriametrics" \
    "${REPO_ROOT}/components/vmagent" \
    "${REPO_ROOT}/components/vmalert" \
    "${REPO_ROOT}/components/nightingale" \
    "${REPO_ROOT}/components/categraf"
  [ "$status" -ne 0 ]
  run grep -R -nE ':latest|privileged:[[:space:]]*true' \
    "${REPO_ROOT}/components/victoriametrics" \
    "${REPO_ROOT}/components/vmagent" \
    "${REPO_ROOT}/components/vmalert" \
    "${REPO_ROOT}/components/nightingale" \
    "${REPO_ROOT}/components/categraf"
  [ "$status" -ne 0 ]
}

@test "Nightingale uses external support services without publishing their ports" {
  local compose_file="${REPO_ROOT}/components/nightingale/deploy/compose/compose.yaml"
  run grep -E 'NIGHTINGALE_(MYSQL_DSN|REDIS_ADDRESS|VICTORIAMETRICS_URL)' "${compose_file}"
  [ "$status" -eq 0 ]
  run grep -E '^[[:space:]]+(mysql|redis):|3306:3306|6379:6379' "${compose_file}"
  [ "$status" -ne 0 ]
}

@test "Categraf host mounts exist only in the opt-in host collection profile" {
  local base="${REPO_ROOT}/components/categraf/deploy/compose/compose.yaml"
  local overlay="${REPO_ROOT}/components/categraf/deploy/compose/host-collection.compose.yaml"
  run grep -E '/proc|/sys|/:/host' "${base}"
  [ "$status" -ne 0 ]
  run grep -F 'host-collection' "${overlay}"
  [ "$status" -eq 0 ]
  run grep -E '/proc|/sys|/:/host' "${overlay}"
  [ "$status" -eq 0 ]
}

@test "new component hooks clearly reject unsupported modes" {
  local component hook
  for component in "${COMPONENTS[@]}"; do
    hook="${REPO_ROOT}/components/${component}/hooks/lifecycle.sh"
    run bash -c 'source "$1"; component_lifecycle status native ""' _ "${hook}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unsupported"* ]]
  done
}

@test "Nightingale exact-version assets can be prepared from an offline source" {
  local source_dir="${BATS_TEST_TMPDIR}/nightingale-assets"
  local target_dir="${BATS_TEST_TMPDIR}/prepared"
  mkdir -p "${source_dir}"
  printf '%s\n' 'CREATE TABLE test (id int);' > "${source_dir}/n9e.sql"
  printf '%s\n' '[Global]' > "${source_dir}/config.toml"
  export MH_NIGHTINGALE_ASSET_SOURCE_DIR="${source_dir}"
  source "${REPO_ROOT}/components/nightingale/hooks/lifecycle.sh"

  nightingale_prepare_release_assets 7.7.0 "${target_dir}"

  [ -f "${target_dir}/n9e.sql" ]
  [ -f "${target_dir}/config.toml.upstream" ]
}
