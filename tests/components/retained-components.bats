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
  export MH_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  export MH_SKIP_OWNERSHIP=1
  export ALERTMANAGER_IMAGE="quay.io/prometheus/alertmanager:v0.28.1"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\\n" "$*" >> "${MH_DOCKER_LOG}"' \
    'if [[ "$1 $2" == "image inspect" ]]; then printf "quay.io/prometheus/alertmanager@sha256:abcdef\n"; exit 0; fi' \
    'if [[ "$1" == "compose" && "$*" == *"ps -q"* ]]; then printf "container-id\n"; exit 0; fi' \
    'if [[ "$1" == "inspect" ]]; then printf "running healthy\n"; exit 0; fi' \
    > "${fake_docker}"
  chmod +x "${fake_docker}"

  source "${REPO_ROOT}/components/alertmanager/hooks/lifecycle.sh"
  component_lifecycle install compose ""

  [ -f "${MH_CONFIG_DIR}/alertmanager/alertmanager.yml" ]
  [ -d "${MH_DATA_DIR}/alertmanager" ]
  [ -f "${MH_STATE_DIR}/component/alertmanager.json" ]
  run grep -F '@sha256:abcdef' "${MH_STATE_DIR}/component/alertmanager.images.tsv"
  [ "$status" -eq 0 ]
  run grep -F 'up -d' "${MH_DOCKER_LOG}"
  [ "$status" -eq 0 ]
}

@test "component dry-run renders Compose without preparing paths or starting services" {
  local fake_docker="${BATS_TEST_TMPDIR}/docker"
  export MH_DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
  export MH_DOCKER_BIN="${fake_docker}"
  export MH_CONFIG_DIR="${BATS_TEST_TMPDIR}/config"
  export MH_DATA_DIR="${BATS_TEST_TMPDIR}/data"
  export MH_DRY_RUN=1
  export ALERTMANAGER_IMAGE="quay.io/prometheus/alertmanager:v0.28.1"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "${MH_DOCKER_LOG}"' > "${fake_docker}"
  chmod +x "${fake_docker}"

  source "${REPO_ROOT}/components/alertmanager/hooks/lifecycle.sh"
  component_lifecycle install compose ""

  [ ! -e "${MH_CONFIG_DIR}" ]
  [ ! -e "${MH_DATA_DIR}" ]
  run grep -F ' config' "${MH_DOCKER_LOG}"
  [ "$status" -eq 0 ]
  run grep -F 'up -d' "${MH_DOCKER_LOG}"
  [ "$status" -ne 0 ]
}

@test "component dry-run is non-mutating for every lifecycle action" {
  local fake_docker="${BATS_TEST_TMPDIR}/docker"
  local action
  export MH_DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
  export MH_DOCKER_BIN="${fake_docker}"
  export MH_CONFIG_DIR="${BATS_TEST_TMPDIR}/config"
  export MH_DATA_DIR="${BATS_TEST_TMPDIR}/data"
  export MH_DRY_RUN=1 MH_PURGE_DATA=1 MH_ASSUME_YES=1
  export ALERTMANAGER_IMAGE="quay.io/prometheus/alertmanager:v0.28.1"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "${MH_DOCKER_LOG}"' > "${fake_docker}"
  chmod +x "${fake_docker}"
  source "${REPO_ROOT}/components/alertmanager/hooks/lifecycle.sh"

  for action in install upgrade restore uninstall; do
    : > "${MH_DOCKER_LOG}"
    component_lifecycle "${action}" compose ""
    [ ! -e "${MH_CONFIG_DIR}" ]
    [ ! -e "${MH_DATA_DIR}" ]
    run grep -E 'up|down|pull|stop|restart' "${MH_DOCKER_LOG}"
    [ "$status" -ne 0 ]
  done
}

@test "failed component upgrade restores previous config and image digest" {
  local fake_docker="${BATS_TEST_TMPDIR}/docker"
  export MH_DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
  export MH_DOCKER_STATE="${BATS_TEST_TMPDIR}/docker-state"
  export MH_DOCKER_BIN="${fake_docker}"
  export MH_CONFIG_DIR="${BATS_TEST_TMPDIR}/config"
  export MH_DATA_DIR="${BATS_TEST_TMPDIR}/data"
  export MH_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  export MH_BACKUP_DIR="${BATS_TEST_TMPDIR}/backups"
  export MH_SKIP_OWNERSHIP=1
  export MH_HEALTH_MAX_ATTEMPTS=1 MH_HEALTH_INTERVAL=0
  export ALERTMANAGER_IMAGE="quay.io/prometheus/alertmanager:v0.29.0"
  mkdir -p "${MH_CONFIG_DIR}/alertmanager" "${MH_DATA_DIR}/alertmanager" "${MH_STATE_DIR}/component"
  printf 'old config\n' > "${MH_CONFIG_DIR}/alertmanager/alertmanager.yml"
  printf '{"status":"healthy"}\n' > "${MH_STATE_DIR}/component/alertmanager.json"
  printf 'ALERTMANAGER_IMAGE\tquay.io/prometheus/alertmanager@sha256:old\n' \
    > "${MH_STATE_DIR}/component/alertmanager.images.tsv"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "image=%s command=%s\n" "${ALERTMANAGER_IMAGE:-}" "$*" >> "${MH_DOCKER_LOG}"' \
    'if [[ "$1 $2" == "image inspect" ]]; then printf "quay.io/prometheus/alertmanager@sha256:new\n"; exit 0; fi' \
    'if [[ "$1" == "compose" && "$*" == *"up -d"* ]]; then' \
    '  count=0; [[ -f "${MH_DOCKER_STATE}" ]] && count="$(cat "${MH_DOCKER_STATE}")"; count=$((count + 1)); printf "%s" "${count}" > "${MH_DOCKER_STATE}"' \
    '  [[ "${count}" == "1" ]] && printf "new config\n" > "${MH_CONFIG_DIR}/alertmanager/alertmanager.yml"' \
    '  exit 0' \
    'fi' \
    'if [[ "$1" == "compose" && "$*" == *"ps -q"* ]]; then printf "container-id\n"; exit 0; fi' \
    'if [[ "$1" == "inspect" ]]; then [[ "$(cat "${MH_DOCKER_STATE}")" == "1" ]] && printf "running unhealthy\n" || printf "running healthy\n"; exit 0; fi' \
    'exit 0' > "${fake_docker}"
  chmod +x "${fake_docker}"
  source "${REPO_ROOT}/components/alertmanager/hooks/lifecycle.sh"

  run component_lifecycle upgrade compose ""

  [ "$status" -ne 0 ]
  [ "$(cat "${MH_CONFIG_DIR}/alertmanager/alertmanager.yml")" = "old config" ]
  run grep -F $'ALERTMANAGER_IMAGE\tquay.io/prometheus/alertmanager@sha256:old' \
    "${MH_STATE_DIR}/component/alertmanager.images.tsv"
  [ "$status" -eq 0 ]
  run grep -F 'image=quay.io/prometheus/alertmanager@sha256:old' "${MH_DOCKER_LOG}"
  [ "$status" -eq 0 ]
}

@test "failed component restore rolls back config data and image state" {
  local fake_docker="${BATS_TEST_TMPDIR}/docker"
  local restore_path
  export MH_DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
  export MH_DOCKER_STATE="${BATS_TEST_TMPDIR}/docker-state"
  export MH_DOCKER_BIN="${fake_docker}"
  export MH_CONFIG_DIR="${BATS_TEST_TMPDIR}/config"
  export MH_DATA_DIR="${BATS_TEST_TMPDIR}/data"
  export MH_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  export MH_BACKUP_DIR="${BATS_TEST_TMPDIR}/backups"
  export MH_SKIP_OWNERSHIP=1
  export MH_HEALTH_MAX_ATTEMPTS=1 MH_HEALTH_INTERVAL=0
  mkdir -p "${MH_CONFIG_DIR}/alertmanager" "${MH_DATA_DIR}/alertmanager" "${MH_STATE_DIR}/component"
  printf 'candidate config\n' > "${MH_CONFIG_DIR}/alertmanager/alertmanager.yml"
  printf 'candidate data\n' > "${MH_DATA_DIR}/alertmanager/payload"
  source "${REPO_ROOT}/lib/core/backup.sh"
  mh_backup_create component alertmanager \
    "${MH_CONFIG_DIR}/alertmanager" "${MH_DATA_DIR}/alertmanager"
  restore_path="${MH_BACKUP_PATH}"
  printf 'current config\n' > "${MH_CONFIG_DIR}/alertmanager/alertmanager.yml"
  printf 'current data\n' > "${MH_DATA_DIR}/alertmanager/payload"
  printf '{"status":"healthy"}\n' > "${MH_STATE_DIR}/component/alertmanager.json"
  printf 'ALERTMANAGER_IMAGE\tquay.io/prometheus/alertmanager@sha256:old\n' \
    > "${MH_STATE_DIR}/component/alertmanager.images.tsv"
  export MH_RESTORE_PATH="${restore_path}"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "image=%s command=%s\n" "${ALERTMANAGER_IMAGE:-}" "$*" >> "${MH_DOCKER_LOG}"' \
    'if [[ "$1" == "compose" && "$*" == *"up -d"* ]]; then' \
    '  count=0; [[ -f "${MH_DOCKER_STATE}" ]] && count="$(cat "${MH_DOCKER_STATE}")"; count=$((count + 1)); printf "%s" "${count}" > "${MH_DOCKER_STATE}"; exit 0' \
    'fi' \
    'if [[ "$1" == "compose" && "$*" == *"ps -q"* ]]; then printf "container-id\n"; exit 0; fi' \
    'if [[ "$1" == "inspect" ]]; then [[ "$(cat "${MH_DOCKER_STATE}")" == "1" ]] && printf "running unhealthy\n" || printf "running healthy\n"; exit 0; fi' \
    'exit 0' > "${fake_docker}"
  chmod +x "${fake_docker}"
  source "${REPO_ROOT}/components/alertmanager/hooks/lifecycle.sh"

  run component_lifecycle restore compose ""

  [ "$status" -ne 0 ]
  [ "$(cat "${MH_CONFIG_DIR}/alertmanager/alertmanager.yml")" = "current config" ]
  [ "$(cat "${MH_DATA_DIR}/alertmanager/payload")" = "current data" ]
  run grep -F 'image=quay.io/prometheus/alertmanager@sha256:old' "${MH_DOCKER_LOG}"
  [ "$status" -eq 0 ]
}

@test "real component purge removes only its bind-mounted config data and state" {
  local fake_docker="${BATS_TEST_TMPDIR}/docker"
  export MH_DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
  export MH_DOCKER_BIN="${fake_docker}"
  export MH_CONFIG_DIR="${BATS_TEST_TMPDIR}/config"
  export MH_DATA_DIR="${BATS_TEST_TMPDIR}/data"
  export MH_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  export MH_ASSUME_YES=1 MH_PURGE_DATA=1
  export ALERTMANAGER_IMAGE='quay.io/prometheus/alertmanager@sha256:old'
  mkdir -p "${MH_CONFIG_DIR}/alertmanager" "${MH_DATA_DIR}/alertmanager" "${MH_STATE_DIR}/component"
  printf 'state\n' > "${MH_STATE_DIR}/component/alertmanager.json"
  printf 'ALERTMANAGER_IMAGE\tquay.io/prometheus/alertmanager@sha256:old\n' \
    > "${MH_STATE_DIR}/component/alertmanager.images.tsv"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "${MH_DOCKER_LOG}"' > "${fake_docker}"
  chmod +x "${fake_docker}"
  source "${REPO_ROOT}/components/alertmanager/hooks/lifecycle.sh"

  component_lifecycle uninstall compose ""

  [ ! -e "${MH_CONFIG_DIR}/alertmanager" ]
  [ ! -e "${MH_DATA_DIR}/alertmanager" ]
  [ ! -e "${MH_STATE_DIR}/component/alertmanager.json" ]
  [ ! -e "${MH_STATE_DIR}/component/alertmanager.images.tsv" ]
  run grep -F 'down --volumes' "${MH_DOCKER_LOG}"
  [ "$status" -eq 0 ]
}
