#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "${repo_root}"
status=0

while IFS= read -r -d '' file; do
  if grep -E '(vsphere_password|login_password|db_password|AccessSecret|APPSECRET)[[:space:]]*[:=]' "${file}" \
    | grep -Evq '^[[:space:]]*#|[:=][[:space:]]*$|\$\{[A-Z][A-Z0-9_]*\}|<REPLACE_ME>|__MYSQL_PASSWORD__'; then
    printf 'possible assigned secret: %s\n' "${file}" >&2
    status=1
  fi
  if grep -Eq 'BEGIN [A-Z ]*PRIVATE KEY|(ghp|github_pat|xox[baprs])_[A-Za-z0-9_-]{16,}' "${file}"; then
    printf 'possible token or private key: %s\n' "${file}" >&2
    status=1
  fi
done < <(find . \
  -path './.git' -prune -o \
  -path './.tools' -prune -o \
  -path './.superpowers' -prune -o \
  -path './packages' -prune -o \
  -type f \( -name '*.yml' -o -name '*.yaml' -o -name '*.conf' -o -name '*.toml' -o -name '*.env' -o -name '*.example' -o -name '*.pem' -o -name '*.key' \) \
  -print0)

exit "${status}"
