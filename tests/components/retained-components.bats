#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
  VALIDATOR="${REPO_ROOT}/tools/dev/validate-metadata.rb"
  COMPONENTS=(prometheus alertmanager grafana blackbox-exporter vmware-exporter)
}

@test "all retained components satisfy metadata contracts" {
  local component
  for component in "${COMPONENTS[@]}"; do
    run "${VALIDATOR}" component "${REPO_ROOT}/components/${component}/component.yaml"
    [ "$status" -eq 0 ]
    run "${VALIDATOR}" versions "${REPO_ROOT}/components/${component}/versions.yaml"
    [ "$status" -eq 0 ]
  done
}

@test "all retained components provide docs config compose and lifecycle hooks" {
  local component
  for component in "${COMPONENTS[@]}"; do
    [ -f "${REPO_ROOT}/components/${component}/README.md" ]
    [ -d "${REPO_ROOT}/components/${component}/config" ]
    [ -f "${REPO_ROOT}/components/${component}/deploy/compose/compose.yaml" ]
    [ -f "${REPO_ROOT}/components/${component}/hooks/lifecycle.sh" ]
  done
}

@test "legacy component and monolithic compose directories are removed" {
  [ ! -e "${REPO_ROOT}/prometheus" ]
  [ ! -e "${REPO_ROOT}/alertmanager" ]
  [ ! -e "${REPO_ROOT}/blackbox" ]
  [ ! -e "${REPO_ROOT}/vmware" ]
  [ ! -e "${REPO_ROOT}/compose" ]
}

@test "Prometheus and VMware endpoints are parameterized" {
  run grep -R -nE '172\.17\.|vsphere_(host|user|password):[[:space:]]+[^"$<]' \
    "${REPO_ROOT}/components/prometheus" "${REPO_ROOT}/components/vmware-exporter"
  [ "$status" -ne 0 ]
  run grep -R -F '${VMWARE_VSPHERE_PASSWORD}' "${REPO_ROOT}/components/vmware-exporter/config"
  [ "$status" -eq 0 ]
}

@test "Alertmanager uses a safe receiver without PrometheusAlert" {
  run grep -R -n -i 'prometheusalert\|webhook_configs' "${REPO_ROOT}/components/alertmanager"
  [ "$status" -ne 0 ]
  run grep -R -F "receiver: 'null'" "${REPO_ROOT}/components/alertmanager/config"
  [ "$status" -eq 0 ]
}

@test "Compose fragments use resolved images and portable paths" {
  local component compose_file
  for component in "${COMPONENTS[@]}"; do
    compose_file="${REPO_ROOT}/components/${component}/deploy/compose/compose.yaml"
    run grep -nE ':latest|privileged:[[:space:]]*true|172\.17\.|/opt/' "${compose_file}"
    [ "$status" -ne 0 ]
    run grep -F '${MH_CONFIG_DIR}' "${compose_file}"
    [ "$status" -eq 0 ]
    run grep -F '${MH_DATA_DIR}' "${compose_file}"
    [ "$status" -eq 0 ]
    run grep -E 'image:[[:space:]]+\$\{[A-Z0-9_]+_IMAGE' "${compose_file}"
    [ "$status" -eq 0 ]
  done
}

@test "retained lifecycle hooks reject unsupported deployment modes" {
  local component hook
  for component in "${COMPONENTS[@]}"; do
    hook="${REPO_ROOT}/components/${component}/hooks/lifecycle.sh"
    run bash -c 'source "$1"; component_lifecycle status native ""' _ "${hook}"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unsupported"* ]]
  done
}

@test "Compose install prepares component configuration and data paths" {
  local fake_docker="${BATS_TEST_TMPDIR}/docker"
  export MH_DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
  export MH_DOCKER_BIN="${fake_docker}"
  export MH_CONFIG_DIR="${BATS_TEST_TMPDIR}/config"
  export MH_DATA_DIR="${BATS_TEST_TMPDIR}/data"
  export ALERTMANAGER_IMAGE="quay.io/prometheus/alertmanager:v0.28.1"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\\n" "$*" >> "${MH_DOCKER_LOG}"' \
    > "${fake_docker}"
  chmod +x "${fake_docker}"

  source "${REPO_ROOT}/components/alertmanager/hooks/lifecycle.sh"
  component_lifecycle install compose ""

  [ -f "${MH_CONFIG_DIR}/alertmanager/alertmanager.yml" ]
  [ -d "${MH_DATA_DIR}/alertmanager" ]
  run grep -F 'up -d' "${MH_DOCKER_LOG}"
  [ "$status" -eq 0 ]
}
