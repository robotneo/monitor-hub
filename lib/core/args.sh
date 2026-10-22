#!/usr/bin/env bash

if [[ -n "${MH_ARGS_LOADED:-}" ]]; then
  return 0
fi
MH_ARGS_LOADED=1

mh_usage() {
  cat <<'EOF'
Usage:
  monitorctl <component|stack> <name> <action> --mode MODE [options]

Actions:
  install configure start stop restart status upgrade backup restore
  uninstall validate doctor

Modes:
  native docker compose kubernetes

Options:
  --profile PROFILE   Required for stack operations
  --version VERSION   Component: exact version; stack: component=version map
  --dry-run           Validate and render without applying changes
  --yes               Disable interactive confirmation only
  --purge-data        Explicitly allow uninstall to remove component data
  -h, --help          Show this help
EOF
}

mh_valid_identifier() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

mh_parse_args() {
  MH_SHOW_HELP=0
  MH_MODE=""
  MH_PROFILE=""
  MH_VERSION="latest"
  MH_DRY_RUN=0
  MH_ASSUME_YES=0
  MH_PURGE_DATA=0

  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    MH_SHOW_HELP=1
    export MH_SHOW_HELP
    return 0
  fi
  if (( $# < 3 )); then
    printf 'expected kind, name and action\n' >&2
    return 2
  fi

  MH_KIND="$1"
  MH_NAME="$2"
  MH_ACTION="$3"
  shift 3

  case "${MH_KIND}" in
    component | stack) ;;
    *) printf 'unknown kind: %s\n' "${MH_KIND}" >&2; return 2 ;;
  esac
  if ! mh_valid_identifier "${MH_NAME}"; then
    printf 'invalid name: %s\n' "${MH_NAME}" >&2
    return 2
  fi
  case "${MH_ACTION}" in
    install | configure | start | stop | restart | status | upgrade | backup | restore | uninstall | validate | doctor) ;;
    *) printf 'unknown action: %s\n' "${MH_ACTION}" >&2; return 2 ;;
  esac

  while (( $# > 0 )); do
    case "$1" in
      --mode)
        [[ $# -ge 2 ]] || { printf 'missing value for --mode\n' >&2; return 2; }
        MH_MODE="$2"
        shift 2
        ;;
      --profile)
        [[ $# -ge 2 ]] || { printf 'missing value for --profile\n' >&2; return 2; }
        MH_PROFILE="$2"
        shift 2
        ;;
      --version)
        [[ $# -ge 2 ]] || { printf 'missing value for --version\n' >&2; return 2; }
        MH_VERSION="$2"
        shift 2
        ;;
      --dry-run) MH_DRY_RUN=1; shift ;;
      --yes) MH_ASSUME_YES=1; shift ;;
      --purge-data) MH_PURGE_DATA=1; shift ;;
      -h | --help) MH_SHOW_HELP=1; shift ;;
      *) printf 'unknown option: %s\n' "$1" >&2; return 2 ;;
    esac
  done

  case "${MH_MODE}" in
    native | docker | compose | kubernetes) ;;
    "") printf '%s\n' '--mode is required' >&2; return 2 ;;
    *) printf 'unknown mode: %s\n' "${MH_MODE}" >&2; return 2 ;;
  esac
  if [[ "${MH_KIND}" == "stack" && -z "${MH_PROFILE}" ]]; then
    printf '%s\n' '--profile is required for stack operations' >&2
    return 2
  fi
  if [[ -n "${MH_PROFILE}" ]] && ! mh_valid_identifier "${MH_PROFILE}"; then
    printf 'invalid profile: %s\n' "${MH_PROFILE}" >&2
    return 2
  fi

  export MH_KIND MH_NAME MH_ACTION MH_MODE MH_PROFILE MH_VERSION
  export MH_DRY_RUN MH_ASSUME_YES MH_PURGE_DATA MH_SHOW_HELP
}
