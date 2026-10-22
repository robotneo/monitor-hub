#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "${repo_root}"
status=0

while IFS= read -r -d '' file; do
  grep -Iq . "${file}" || continue
  if grep -Ei '(^|[[:space:]"'\''])([A-Za-z0-9_]*(password|passwd|secret|token|api[_-]?key|access[_-]?key|private[_-]?key)[A-Za-z0-9_]*)[[:space:]]*[:=]' "${file}" \
    | grep -Eivq '^[[:space:]]*#|[:=][[:space:]]*$|\$\{[A-Z][A-Z0-9_]*\}|<REPLACE_ME>|__MYSQL_PASSWORD__|example|placeholder|redacted|_PASSWORD(_|__)FILE:[[:space:]]+/run/secrets/|MH_REGISTERED_SECRETS=\(\)|local secret=.*\$\{1:-\}|run mh_log info'; then
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
  -type f \
  -print0)

exit "${status}"
