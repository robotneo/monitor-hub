#!/usr/bin/env bash

if [[ -n "${MH_CONSTANTS_LOADED:-}" ]]; then
  return 0
fi
MH_CONSTANTS_LOADED=1

MH_DEFAULT_ROOT_DIR="/"
MH_DEFAULT_LOG_LEVEL="info"
MH_PROJECT_NAME="monitor-hub"

# Public library constants are consumed by separately sourced modules.
# shellcheck disable=SC2034
readonly MH_DEFAULT_ROOT_DIR MH_DEFAULT_LOG_LEVEL MH_PROJECT_NAME
