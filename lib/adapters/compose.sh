#!/usr/bin/env bash

if [[ -n "${MH_COMPOSE_LOADED:-}" ]]; then
  return 0
fi
MH_COMPOSE_LOADED=1

mh_compose_run() {
  local project_directory="$1"
  shift
  local docker_bin="${MH_DOCKER_BIN:-docker}"
  local files_value="${MH_COMPOSE_FILES:-compose.yaml}"
  local file
  local -a command
  local -a files

  IFS=: read -r -a files <<< "${files_value}"
  command=("${docker_bin}" compose --project-directory "${project_directory}")
  for file in "${files[@]}"; do
    command+=(-f "${file}")
  done
  command+=("$@")
  "${command[@]}"
}

mh_compose_wait_healthy() {
  local project_directory="$1"
  local docker_bin="${MH_DOCKER_BIN:-docker}"
  local max_attempts="${MH_HEALTH_MAX_ATTEMPTS:-60}"
  local interval="${MH_HEALTH_INTERVAL:-5}"
  local attempt id state health all_ready
  local -a container_ids

  for (( attempt = 1; attempt <= max_attempts; attempt += 1 )); do
    container_ids=()
    while IFS= read -r id; do
      [[ -n "${id}" ]] && container_ids+=("${id}")
    done < <(mh_compose_run "${project_directory}" ps -q)
    all_ready=1
    if (( ${#container_ids[@]} == 0 )); then
      all_ready=0
    fi
    for id in "${container_ids[@]}"; do
      [[ -n "${id}" ]] || continue
      if ! read -r state health < <("${docker_bin}" inspect --format \
        '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${id}"); then
        all_ready=0
        continue
      fi
      if [[ "${state}" != "running" || ( "${health}" != "healthy" && "${health}" != "none" ) ]]; then
        all_ready=0
      fi
    done
    if [[ "${all_ready}" == "1" ]]; then
      return 0
    fi
    if (( attempt < max_attempts )) && [[ "${interval}" != "0" ]]; then
      sleep "${interval}"
    fi
  done

  printf 'Compose health check failed after %s attempt(s)\n' "${max_attempts}" >&2
  mh_compose_run "${project_directory}" ps >&2 || true
  return 1
}

mh_compose_assert_metrics_query() {
  local project_directory="$1" response
  if ! response="$(mh_compose_run "${project_directory}" exec -T victoriametrics \
    wget -q -O - 'http://127.0.0.1:8428/api/v1/query?query=vm_app_version')"; then
    printf 'VictoriaMetrics data-path query failed\n' >&2
    return 1
  fi
  if [[ "${response}" != *'"status":"success"'* ]]; then
    printf 'VictoriaMetrics returned an unsuccessful data-path response\n' >&2
    return 1
  fi
}
