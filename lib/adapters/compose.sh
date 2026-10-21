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
