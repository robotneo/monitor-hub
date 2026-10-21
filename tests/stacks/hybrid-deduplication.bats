#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
  STACK_DIR="${REPO_ROOT}/stacks/hybrid-monitoring"
  COMPOSE_FILE="${STACK_DIR}/deploy/compose/compose.yaml"
}

@test "hybrid stack metadata is valid" {
  run "${REPO_ROOT}/tools/dev/validate-metadata.rb" stack "${STACK_DIR}/stack.yaml"
  [ "$status" -eq 0 ]
}

@test "default collection ownership does not overlap" {
  run grep -F 'enable = false' "${STACK_DIR}/config/categraf/config.toml"
  [ "$status" -eq 0 ]
  run grep -E 'blackbox-exporter:9115|vmware-exporter:9272' "${STACK_DIR}/config/vmagent/prometheus.yml"
  [ "$status" -eq 0 ]
  run grep -E 'blackbox-exporter:9115|vmware-exporter:9272' "${STACK_DIR}/config/categraf/config.toml"
  [ "$status" -ne 0 ]
}

@test "collectors have distinct source labels" {
  run grep -F 'collector = "categraf"' "${STACK_DIR}/config/categraf/config.toml"
  [ "$status" -eq 0 ]
  run grep -F -- '-remoteWrite.label=collector=vmagent' "${COMPOSE_FILE}"
  [ "$status" -eq 0 ]
}

@test "overlap opt-in is documented with an explicit warning and labels" {
  run grep -iE 'warning|警告' "${STACK_DIR}/config/collection-ownership.md"
  [ "$status" -eq 0 ]
  run grep -F 'collector' "${STACK_DIR}/config/collection-ownership.md"
  [ "$status" -eq 0 ]
}

@test "hybrid stack validate reaches Compose" {
  local fake_docker="${BATS_TEST_TMPDIR}/docker"
  export MH_DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "${MH_DOCKER_LOG}"' > "${fake_docker}"
  chmod +x "${fake_docker}"
  export MH_DOCKER_BIN="${fake_docker}"
  export MH_CONFIG_DIR="${BATS_TEST_TMPDIR}/config"
  export MH_DATA_DIR="${BATS_TEST_TMPDIR}/data"
  local digest='@sha256:0000000000000000000000000000000000000000000000000000000000000000'
  export BLACKBOX_EXPORTER_IMAGE="registry.example/blackbox${digest}"
  export VMWARE_EXPORTER_IMAGE="registry.example/vmware${digest}"
  export VMAGENT_IMAGE="registry.example/vmagent${digest}"
  export CATEGRAF_IMAGE="registry.example/categraf${digest}"
  export NIGHTINGALE_IMAGE="registry.example/nightingale${digest}"
  export VICTORIAMETRICS_IMAGE="registry.example/victoriametrics${digest}"
  export GRAFANA_IMAGE="registry.example/grafana${digest}"
  export MYSQL_IMAGE="registry.example/mysql${digest}"
  export REDIS_IMAGE="registry.example/redis${digest}"

  run "${REPO_ROOT}/bin/monitorctl" stack hybrid-monitoring validate --mode compose --profile single-node

  [ "$status" -eq 0 ]
  run grep -F 'config' "${MH_DOCKER_LOG}"
  [ "$status" -eq 0 ]
}
