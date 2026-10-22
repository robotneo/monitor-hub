#!/usr/bin/env bash

if [[ -n "${MH_COMPONENT_COMPOSE_LOADED:-}" ]]; then
  return 0
fi
MH_COMPONENT_COMPOSE_LOADED=1

# shellcheck source=lib/core/component-runtime.sh disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/component-runtime.sh"
