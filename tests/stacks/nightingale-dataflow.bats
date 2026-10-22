#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
  STACK_DIR="${REPO_ROOT}/stacks/nightingale-monitoring"
  COMPOSE_FILE="${STACK_DIR}/deploy/compose/compose.yaml"
}

@test "Nightingale stack metadata is valid and documents cluster boundaries" {
  run "${REPO_ROOT}/tools/dev/validate-metadata.rb" stack "${STACK_DIR}/stack.yaml"
  [ "$status" -eq 0 ]
  [ -f "${STACK_DIR}/profiles/single-node/profile.yaml" ]
  [ -f "${STACK_DIR}/profiles/cluster/README.md" ]
}

@test "MySQL and Redis are internal-only services" {
  run ruby -rpsych -e '
    services = Psych.safe_load(File.read(ARGV.fetch(0))).fetch("services")
    %w[mysql redis].each do |name|
      service = services.fetch(name)
      abort "#{name} publishes host ports" if service.key?("ports")
      abort "#{name} is not internal" unless service.key?("expose")
    end
  ' "${COMPOSE_FILE}"
  [ "$status" -eq 0 ]
}

@test "runtime secrets are generated and mounted as files" {
  run grep -E 'MYSQL_(ROOT_)?PASSWORD_FILE' "${COMPOSE_FILE}"
  [ "$status" -eq 0 ]
  run grep -F 'mh_stack_generate_secret' "${STACK_DIR}/hooks/lifecycle.sh"
  [ "$status" -eq 0 ]
  run grep -R -nE '(password|secret)[[:space:]]*[:=][[:space:]]+[A-Za-z0-9]' "${STACK_DIR}"
  [ "$status" -ne 0 ]
}

@test "fresh MySQL receives exact-version Nightingale bootstrap SQL" {
  run grep -F '/docker-entrypoint-initdb.d/01-n9e.sql:ro' "${COMPOSE_FILE}"
  [ "$status" -eq 0 ]
  run grep -F 'nightingale_prepare_release_assets' "${STACK_DIR}/hooks/lifecycle.sh"
  [ "$status" -eq 0 ]
}

@test "Nightingale waits for healthy support services" {
  run grep -A16 '^  nightingale:' "${COMPOSE_FILE}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'condition: service_healthy'* ]]
  [[ "$output" == *'mysql:'* ]]
  [[ "$output" == *'redis:'* ]]
  [[ "$output" == *'victoriametrics:'* ]]
}

@test "Categraf writes to VictoriaMetrics and Grafana reads it" {
  run grep -F 'http://victoriametrics:8428/api/v1/write' "${STACK_DIR}/config/categraf/config.toml"
  [ "$status" -eq 0 ]
  run grep -F 'http://victoriametrics:8428' "${STACK_DIR}/config/grafana/provisioning/datasources/metrics.yml"
  [ "$status" -eq 0 ]
}

@test "Nightingale stack validate reaches Compose without mutable tags" {
  local fake_docker="${BATS_TEST_TMPDIR}/docker"
  export MH_DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "${MH_DOCKER_LOG}"' > "${fake_docker}"
  chmod +x "${fake_docker}"
  export MH_DOCKER_BIN="${fake_docker}"
  export MH_CONFIG_DIR="${BATS_TEST_TMPDIR}/config"
  export MH_DATA_DIR="${BATS_TEST_TMPDIR}/data"
  local digest='@sha256:0000000000000000000000000000000000000000000000000000000000000000'
  export CATEGRAF_IMAGE="registry.example/categraf${digest}"
  export NIGHTINGALE_IMAGE="registry.example/nightingale${digest}"
  export VICTORIAMETRICS_IMAGE="registry.example/victoriametrics${digest}"
  export GRAFANA_IMAGE="registry.example/grafana${digest}"
  export MYSQL_IMAGE="registry.example/mysql${digest}"
  export REDIS_IMAGE="registry.example/redis${digest}"

  run "${REPO_ROOT}/bin/monitorctl" stack nightingale-monitoring validate --mode compose --profile single-node

  [ "$status" -eq 0 ]
  run grep -F 'config' "${MH_DOCKER_LOG}"
  [ "$status" -eq 0 ]
  run grep -R -nF ':latest' "${STACK_DIR}"
  [ "$status" -ne 0 ]
}

@test "Nightingale stack dry-run does not generate secrets or start services" {
  local fake_docker="${BATS_TEST_TMPDIR}/docker"
  export MH_DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "${MH_DOCKER_LOG}"' > "${fake_docker}"
  chmod +x "${fake_docker}"
  export MH_DOCKER_BIN="${fake_docker}" MH_DRY_RUN=1
  export MH_CONFIG_DIR="${BATS_TEST_TMPDIR}/config" MH_DATA_DIR="${BATS_TEST_TMPDIR}/data"
  local digest='@sha256:0000000000000000000000000000000000000000000000000000000000000000'
  export CATEGRAF_IMAGE="registry.example/categraf${digest}" NIGHTINGALE_IMAGE="registry.example/nightingale${digest}"
  export VICTORIAMETRICS_IMAGE="registry.example/victoriametrics${digest}" GRAFANA_IMAGE="registry.example/grafana${digest}"
  export MYSQL_IMAGE="registry.example/mysql${digest}" REDIS_IMAGE="registry.example/redis${digest}"

  run "${REPO_ROOT}/bin/monitorctl" stack nightingale-monitoring install --mode compose --profile single-node --dry-run

  [ "$status" -eq 0 ]
  [ ! -e "${MH_CONFIG_DIR}" ]
  [ ! -e "${MH_DATA_DIR}" ]
  run grep -F 'up -d' "${MH_DOCKER_LOG}"
  [ "$status" -ne 0 ]
}

@test "Nightingale install prepares SQL, checks health and records immutable image state" {
  local fake_docker="${BATS_TEST_TMPDIR}/docker"
  local asset_source="${BATS_TEST_TMPDIR}/assets"
  export MH_DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >> "${MH_DOCKER_LOG}"' \
    'if [[ "$1" == "compose" && "$*" == *"ps -q"* ]]; then printf "container-id\n"; exit 0; fi' \
    'if [[ "$1" == "inspect" ]]; then printf "running healthy\n"; exit 0; fi' \
    'exit 0' > "${fake_docker}"
  chmod +x "${fake_docker}"
  mkdir -p "${asset_source}"
  printf 'CREATE TABLE n9e_test (id int);\n' > "${asset_source}/n9e.sql"
  printf '[Global]\n' > "${asset_source}/config.toml"
  export MH_DOCKER_BIN="${fake_docker}" MH_SKIP_OWNERSHIP=1
  export MH_CONFIG_DIR="${BATS_TEST_TMPDIR}/config" MH_DATA_DIR="${BATS_TEST_TMPDIR}/data"
  export MH_STATE_DIR="${BATS_TEST_TMPDIR}/state" MH_NIGHTINGALE_ASSET_SOURCE_DIR="${asset_source}"
  export NIGHTINGALE_VERSION=7.7.0
  local digest='@sha256:0000000000000000000000000000000000000000000000000000000000000000'
  export CATEGRAF_IMAGE="registry.example/categraf${digest}" NIGHTINGALE_IMAGE="registry.example/nightingale${digest}"
  export VICTORIAMETRICS_IMAGE="registry.example/victoriametrics${digest}" GRAFANA_IMAGE="registry.example/grafana${digest}"
  export MYSQL_IMAGE="registry.example/mysql${digest}" REDIS_IMAGE="registry.example/redis${digest}"

  run "${REPO_ROOT}/bin/monitorctl" stack nightingale-monitoring install --mode compose --profile single-node

  [ "$status" -eq 0 ]
  [ -f "${MH_CONFIG_DIR}/stacks/nightingale-monitoring/mysql-init/01-n9e.sql" ]
  [ -f "${MH_CONFIG_DIR}/stacks/nightingale-monitoring/mysql-init/checksums.sha256" ]
  [ -f "${MH_STATE_DIR}/stack/nightingale-monitoring.json" ]
  run grep -F 'inspect --format' "${MH_DOCKER_LOG}"
  [ "$status" -eq 0 ]
}
