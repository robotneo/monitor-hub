#!/usr/bin/env bash

if [[ -n "${MH_BACKUP_LOADED:-}" ]]; then
  return 0
fi
MH_BACKUP_LOADED=1

mh_backup_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

mh_backup_create() {
  local kind="$1"
  local name="$2"
  shift 2
  local backup_root="${MH_BACKUP_DIR:-/var/backups/monitor-hub}"
  local timestamp backup_parent index=0 source stored type file relative checksum

  if [[ ! "${kind}" =~ ^[a-z0-9][a-z0-9-]*$ || ! "${name}" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    printf 'invalid backup identifier: %s/%s\n' "${kind}" "${name}" >&2
    return 1
  fi
  timestamp="$(date -u '+%Y%m%dT%H%M%SZ')-$$"
  backup_parent="${backup_root}/${kind}/${name}"
  mkdir -p "${backup_parent}"
  MH_BACKUP_PATH="$(mktemp -d "${backup_parent}/${timestamp}.XXXXXX")" || return 1
  mkdir -p "${MH_BACKUP_PATH}/files"
  printf 'source\tstored\ttype\n' > "${MH_BACKUP_PATH}/manifest.tsv"

  for source in "$@"; do
    [[ -e "${source}" || -L "${source}" ]] || continue
    stored="files/${index}-$(basename "${source}")"
    if [[ -d "${source}" ]]; then type="directory"; else type="file"; fi
    cp -R "${source}" "${MH_BACKUP_PATH}/${stored}"
    printf '%s\t%s\t%s\n' "${source}" "${stored}" "${type}" >> "${MH_BACKUP_PATH}/manifest.tsv"
    index=$((index + 1))
  done

  : > "${MH_BACKUP_PATH}/checksums.sha256"
  while IFS= read -r file; do
    relative="${file#"${MH_BACKUP_PATH}/"}"
    checksum="$(mh_backup_sha256 "${file}")"
    printf '%s  %s\n' "${checksum}" "${relative}" >> "${MH_BACKUP_PATH}/checksums.sha256"
  done < <(find "${MH_BACKUP_PATH}/files" -type f -print)
  export MH_BACKUP_PATH
}

mh_backup_validate() {
  local backup_path="$1"
  shift
  local source stored type allowed_root checksum_tool
  local -a allowed_roots=("$@")
  if [[ ! -r "${backup_path}/manifest.tsv" || ! -r "${backup_path}/checksums.sha256" ]]; then
    printf 'backup manifest is incomplete: %s\n' "${backup_path}" >&2
    return 1
  fi
  if [[ -L "${backup_path}" || -L "${backup_path}/manifest.tsv" || \
    -L "${backup_path}/checksums.sha256" || -L "${backup_path}/files" ]]; then
    printf 'backup metadata contains a symbolic link: %s\n' "${backup_path}" >&2
    return 1
  fi
  if (( ${#allowed_roots[@]} == 0 )); then
    printf 'restore requires at least one allowed destination root\n' >&2
    return 1
  fi
  if find "${backup_path}/files" -type l -print -quit 2>/dev/null | grep -q .; then
    printf 'backup payload contains a symbolic link: %s\n' "${backup_path}" >&2
    return 1
  fi

  if command -v sha256sum >/dev/null 2>&1; then checksum_tool=sha256sum
  else checksum_tool=shasum
  fi
  if [[ "${checksum_tool}" == "sha256sum" ]]; then
    if ! (cd "${backup_path}" && sha256sum -c checksums.sha256 >/dev/null); then
      printf 'backup checksum verification failed: %s\n' "${backup_path}" >&2
      return 1
    fi
  elif ! (cd "${backup_path}" && shasum -a 256 -c checksums.sha256 >/dev/null); then
    printf 'backup checksum verification failed: %s\n' "${backup_path}" >&2
    return 1
  fi

  while IFS=$'\t' read -r source stored type; do
    [[ "${source}" == "source" ]] && continue
    if [[ -z "${source}" || "${source}" != /* || \
      "${source}" == *'/../'* || "${source}" == *'/..' || \
      "${source}" == *'/./'* || "${source}" == *'/.' ]]; then
      printf 'unsafe restore destination: %s\n' "${source}" >&2
      return 1
    fi
    if [[ "${stored}" != files/* || "${stored}" == *'/../'* || \
      "${stored}" == '../'* || "${stored}" == *'/..' || \
      "${stored}" == *'/./'* || "${stored}" == *'/.' || "${stored}" == /* ]]; then
      printf 'unsafe stored path in backup manifest: %s\n' "${stored}" >&2
      return 1
    fi
    if [[ "${type}" != "file" && "${type}" != "directory" ]]; then
      printf 'invalid backup entry type: %s\n' "${type}" >&2
      return 1
    fi
    if [[ ! -e "${backup_path}/${stored}" || -L "${backup_path}/${stored}" ]]; then
      printf 'backup payload is missing or unsafe: %s\n' "${stored}" >&2
      return 1
    fi
    local destination_allowed=0
    for allowed_root in "${allowed_roots[@]}"; do
      if [[ -n "${allowed_root}" && "${allowed_root}" == /* && \
        "${source}" == "${allowed_root}" ]]; then
        destination_allowed=1
        break
      fi
    done
    if [[ "${destination_allowed}" != "1" ]]; then
      printf 'restore destination is outside allowed roots: %s\n' "${source}" >&2
      return 1
    fi
  done < "${backup_path}/manifest.tsv"

}

mh_backup_restore() {
  local backup_path="$1"
  shift
  local source stored type
  mh_backup_validate "${backup_path}" "$@" || return 1
  while IFS=$'\t' read -r source stored type; do
    [[ "${source}" == "source" ]] && continue
    if [[ -e "${source}" || -L "${source}" ]]; then
      rm -rf -- "${source}"
    fi
    mkdir -p "$(dirname "${source}")"
    cp -R "${backup_path}/${stored}" "${source}"
  done < "${backup_path}/manifest.tsv"
}
