#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
  cd "${REPO_ROOT}"
}

@test "tracked configuration contains no assigned secret values" {
  run bash -c '
    result=0
    while IFS= read -r file; do
      [ -f "${file}" ] || continue
      if grep -E "(vsphere_password|login_password|db_password|AccessSecret|APPSECRET)[[:space:]]*[:=]" "${file}" \
        | grep -Evq "^[[:space:]]*#|[:=][[:space:]]*$|\\$\\{[A-Z][A-Z0-9_]*\\}|<REPLACE_ME>"; then
        printf "%s\n" "${file}"
        result=1
      fi
    done < <(git ls-files "*.yml" "*.yaml" "*.conf" "*.env")
    exit "${result}"
  '

  [ "${status}" -eq 0 ]
}

@test "tracked configuration contains no webhook tokens or private keys" {
  run git grep -IlE \
    '(access_token|webhook/send\?key)=[^$<{[:space:]]+|BEGIN [A-Z ]*PRIVATE KEY' \
    -- '*.yml' '*.yaml' '*.conf' '*.env' '*.pem' '*.key'

  [ "${status}" -eq 1 ]
}

@test "PrometheusAlert configuration is not tracked" {
  run find alert -type f -print

  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}
