#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
  MH_COMPOSE_FILES="${BATS_TEST_TMPDIR}/compose.yaml"
  touch "${MH_COMPOSE_FILES}"
  export MH_COMPOSE_FILES MH_HEALTH_MAX_ATTEMPTS=1 MH_HEALTH_INTERVAL=0
  source "${REPO_ROOT}/lib/adapters/compose.sh"
}

write_fake_docker() {
  local state="$1" health="$2"
  MH_DOCKER_BIN="${BATS_TEST_TMPDIR}/docker"
  export MH_DOCKER_BIN
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "$1" == "compose" && "$*" == *"ps -q"* ]]; then printf "container-id\n"; exit 0; fi' \
    "if [[ \"\$1\" == \"inspect\" ]]; then printf '%s %s\\n' '${state}' '${health}'; exit 0; fi" \
    'exit 1' > "${MH_DOCKER_BIN}"
  chmod +x "${MH_DOCKER_BIN}"
}

@test "Compose health gate accepts running healthy containers" {
  write_fake_docker running healthy

  run mh_compose_wait_healthy "${BATS_TEST_TMPDIR}"

  [ "$status" -eq 0 ]
}

@test "Compose health gate accepts services without a declared healthcheck" {
  write_fake_docker running none

  run mh_compose_wait_healthy "${BATS_TEST_TMPDIR}"

  [ "$status" -eq 0 ]
}

@test "Compose health gate rejects unhealthy containers" {
  write_fake_docker running unhealthy

  run mh_compose_wait_healthy "${BATS_TEST_TMPDIR}"

  [ "$status" -ne 0 ]
  [[ "$output" == *"health check failed"* ]]
}

@test "Compose health gate rejects stopped containers" {
  write_fake_docker exited none

  run mh_compose_wait_healthy "${BATS_TEST_TMPDIR}"

  [ "$status" -ne 0 ]
}

@test "metrics data-path check requires a successful VictoriaMetrics query" {
  MH_DOCKER_BIN="${BATS_TEST_TMPDIR}/docker"
  export MH_DOCKER_BIN
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "$1" == "compose" && "$*" == *"exec -T victoriametrics"* ]]; then printf '\''{"status":"success","data":{"result":[]}}\n'\''; exit 0; fi' \
    'exit 1' > "${MH_DOCKER_BIN}"
  chmod +x "${MH_DOCKER_BIN}"

  run mh_compose_assert_metrics_query "${BATS_TEST_TMPDIR}"

  [ "$status" -eq 0 ]
}
