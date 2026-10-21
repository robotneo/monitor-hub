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
  local timestamp index=0 source stored type file relative checksum

  if [[ ! "${kind}" =~ ^[a-z0-9][a-z0-9-]*$ || ! "${name}" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    printf 'invalid backup identifier: %s/%s\n' "${kind}" "${name}" >&2
    return 1
  fi
  timestamp="$(date -u '+%Y%m%dT%H%M%SZ')-$$"
  MH_BACKUP_PATH="${backup_root}/${kind}/${name}/${timestamp}"
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

mh_backup_restore() {
  local backup_path="$1"
  local source stored type
  if [[ ! -r "${backup_path}/manifest.tsv" || ! -r "${backup_path}/checksums.sha256" ]]; then
    printf 'backup manifest is incomplete: %s\n' "${backup_path}" >&2
    return 1
  fi

  while IFS=$'\t' read -r source stored type; do
    [[ "${source}" == "source" ]] && continue
    [[ -n "${source}" && -e "${backup_path}/${stored}" ]] || continue
    if [[ -e "${source}" || -L "${source}" ]]; then
      rm -rf "${source}"
    fi
    mkdir -p "$(dirname "${source}")"
    cp -R "${backup_path}/${stored}" "${source}"
  done < "${backup_path}/manifest.tsv"
}
