#!/usr/bin/env bash

MH_COMPONENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MH_COMPONENT_REPO_ROOT="$(cd "${MH_COMPONENT_DIR}/../.." && pwd -P)"
# shellcheck source=lib/adapters/compose.sh disable=SC1091
source "${MH_COMPONENT_REPO_ROOT}/lib/adapters/compose.sh"
# shellcheck source=lib/core/backup.sh disable=SC1091
source "${MH_COMPONENT_REPO_ROOT}/lib/core/backup.sh"
# shellcheck source=lib/core/component-compose.sh disable=SC1091
source "${MH_COMPONENT_REPO_ROOT}/lib/core/component-compose.sh"

component_lifecycle() {
  mh_component_compose_lifecycle vmware-exporter VMWARE_EXPORTER_IMAGE "${MH_COMPONENT_DIR}" "$@"
}
