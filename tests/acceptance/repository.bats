#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
  cd "${REPO_ROOT}"
}

@test "README is a bilingual monitor-hub entry point without legacy branding" {
  run grep -E 'monitor-hub|Monitor Hub' README.md
  [ "$status" -eq 0 ]
  run grep -E '快速开始|Quick start' README.md
  [ "$status" -eq 0 ]
  run grep -E 'prometheus-everything|PrometheusAlert' README.md
  [ "$status" -ne 0 ]
}

@test "operator guides cover every implemented deployment mode and lifecycle" {
  for guide in quick-start offline-installation backup-restore upgrade-rollback secrets troubleshooting migration-from-legacy-layout; do
    [ -f "docs/guides/${guide}.md" ]
  done
  run grep -R -E 'install|安装' docs/guides
  [ "$status" -eq 0 ]
  run grep -R -E 'uninstall|卸载' docs/guides
  [ "$status" -eq 0 ]
  run grep -R -E 'Compose|compose' docs/guides
  [ "$status" -eq 0 ]
}

@test "all three stacks declare support maturity" {
  local stack
  for stack in victoriametrics-monitoring nightingale-monitoring hybrid-monitoring; do
    run grep -A2 '^support:' "stacks/${stack}/stack.yaml"
    [ "$status" -eq 0 ]
    [[ "$output" == *'level:'* ]]
  done
}

@test "removed legacy combinations and PrometheusAlert do not exist" {
  [ ! -e prometheus-vmware ]
  [ ! -e stacks/prometheus-vmware ]
  [ ! -e alert ]
  run find . -path './.git' -prune -o -type f -iname '*prometheusalert*' -print
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "CI and repository commands expose lint validate test and smoke" {
  [ -f .github/workflows/validate.yml ]
  [ -f .github/workflows/compose-smoke.yml ]
  for target in lint validate test smoke; do
    run grep -E "^${target}:" Makefile
    [ "$status" -eq 0 ]
  done
}

@test "secret scan covers the complete worktree" {
  run tools/dev/scan-secrets.sh
  [ "$status" -eq 0 ]
}

@test "reference docs explain compatibility and repository extension" {
  [ -f docs/reference/compatibility-matrix.md ]
  [ -f docs/reference/adding-a-component.md ]
  [ -f docs/reference/adding-a-stack.md ]
  run grep -E 'Ubuntu 22.04|Ubuntu 24.04|Rocky Linux 8|Rocky Linux 9' docs/reference/compatibility-matrix.md
  [ "$status" -eq 0 ]
}
