#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
validator="${repo_root}/tools/dev/validate-metadata.rb"
file=""

for file in "${repo_root}"/components/*/component.yaml; do "${validator}" component "${file}"; done
for file in "${repo_root}"/components/*/versions.yaml; do "${validator}" versions "${file}"; done
for file in "${repo_root}"/stacks/*/stack.yaml; do "${validator}" stack "${file}"; done
ruby -e 'require "psych"; ARGV.each { |path| Psych.parse_file(path) }' \
  "${repo_root}"/components/*/deploy/compose/*.yaml \
  "${repo_root}"/stacks/*/deploy/compose/*.yaml
"${repo_root}/tools/dev/scan-secrets.sh"
