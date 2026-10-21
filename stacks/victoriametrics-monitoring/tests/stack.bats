#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd -P)"
  STACK_DIR="${REPO_ROOT}/stacks/victoriametrics-monitoring"
  COMPOSE_FILE="${STACK_DIR}/deploy/compose/compose.yaml"
  MONITORCTL="${REPO_ROOT}/bin/monitorctl"
}

@test "stack metadata and single-node profile satisfy the contract" {
  run "${REPO_ROOT}/tools/dev/validate-metadata.rb" stack "${STACK_DIR}/stack.yaml"
  [ "$status" -eq 0 ]
  [ -f "${STACK_DIR}/profiles/single-node/profile.yaml" ]
  [ -f "${STACK_DIR}/profiles/cluster/README.md" ]
}

@test "metrics and alerts follow the documented internal data flow" {
  run grep -F -- '-remoteWrite.url=http://victoriametrics:8428/api/v1/write' "${COMPOSE_FILE}"
  [ "$status" -eq 0 ]
  run grep -F -- '-datasource.url=http://victoriametrics:8428' "${COMPOSE_FILE}"
  [ "$status" -eq 0 ]
  run grep -F -- '-notifier.url=http://alertmanager:9093' "${COMPOSE_FILE}"
  [ "$status" -eq 0 ]
  run grep -F 'http://victoriametrics:8428' "${STACK_DIR}/config/grafana/provisioning/datasources/metrics.yml"
  [ "$status" -eq 0 ]
}

@test "only Grafana is published and stateful services use persistent paths" {
  run grep -cE '^[[:space:]]{4}ports:' "${COMPOSE_FILE}"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
  run grep -F '${MH_DATA_DIR}/stacks/victoriametrics-monitoring/victoriametrics:/storage' "${COMPOSE_FILE}"
  [ "$status" -eq 0 ]
  run grep -F '${MH_DATA_DIR}/stacks/victoriametrics-monitoring/grafana:/var/lib/grafana' "${COMPOSE_FILE}"
  [ "$status" -eq 0 ]
}

@test "services are non-root and never privileged by default" {
  run grep -nE 'privileged:[[:space:]]*true|user:[[:space:]]*["'\'']?0([:"'\'']|$)' "${COMPOSE_FILE}"
  [ "$status" -ne 0 ]
  run grep -cE '^[[:space:]]{4}user:' "${COMPOSE_FILE}"
  [ "$status" -eq 0 ]
  [ "$output" -eq 7 ]
}

@test "VMware exporter is disabled unless its explicit profile is enabled" {
  run grep -A8 '^  vmware-exporter:' "${COMPOSE_FILE}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'profiles: ["vmware"]'* ]]
  run grep -F 'VMAGENT_CONFIG_FILE' "${STACK_DIR}/deploy/compose/.env.example"
  [ "$status" -eq 0 ]
}

@test "Alertmanager starts with the safe null receiver" {
  run grep -F "receiver: 'null'" "${STACK_DIR}/config/alertmanager/alertmanager.yml"
  [ "$status" -eq 0 ]
  run grep -F "name: 'null'" "${STACK_DIR}/config/alertmanager/alertmanager.yml"
  [ "$status" -eq 0 ]
}

@test "stack lifecycle validates the single-node compose profile" {
  local fake_docker="${BATS_TEST_TMPDIR}/docker"
  export MH_DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "${MH_DOCKER_LOG}"' > "${fake_docker}"
  chmod +x "${fake_docker}"
  export MH_DOCKER_BIN="${fake_docker}"
  export MH_CONFIG_DIR="${BATS_TEST_TMPDIR}/config"
  export MH_DATA_DIR="${BATS_TEST_TMPDIR}/data"
  export BLACKBOX_EXPORTER_IMAGE='registry.example/blackbox@sha256:0000000000000000000000000000000000000000000000000000000000000000'
  export VMWARE_EXPORTER_IMAGE='registry.example/vmware@sha256:0000000000000000000000000000000000000000000000000000000000000000'
  export VMAGENT_IMAGE='registry.example/vmagent@sha256:0000000000000000000000000000000000000000000000000000000000000000'
  export VICTORIAMETRICS_IMAGE='registry.example/victoriametrics@sha256:0000000000000000000000000000000000000000000000000000000000000000'
  export GRAFANA_IMAGE='registry.example/grafana@sha256:0000000000000000000000000000000000000000000000000000000000000000'
  export VMALERT_IMAGE='registry.example/vmalert@sha256:0000000000000000000000000000000000000000000000000000000000000000'
  export ALERTMANAGER_IMAGE='registry.example/alertmanager@sha256:0000000000000000000000000000000000000000000000000000000000000000'

  run "${MONITORCTL}" stack victoriametrics-monitoring validate --mode compose --profile single-node

  [ "$status" -eq 0 ]
  run grep -F 'compose --project-directory' "${MH_DOCKER_LOG}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'config'* ]]
}
