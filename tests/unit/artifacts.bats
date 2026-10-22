#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd -P)"
  FIXTURES="${REPO_ROOT}/tests/fixtures/releases"
  MH_COMPONENTS_DIR="${BATS_TEST_TMPDIR}/components"
  MH_PACKAGES_DIR="${BATS_TEST_TMPDIR}/packages"
  MH_CACHE_DIR="${BATS_TEST_TMPDIR}/cache"
  MH_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  mkdir -p "${MH_COMPONENTS_DIR}/demo" "${MH_PACKAGES_DIR}" "${MH_CACHE_DIR}" "${MH_STATE_DIR}"
  export MH_COMPONENTS_DIR MH_PACKAGES_DIR MH_CACHE_DIR MH_STATE_DIR
  # shellcheck source=../../lib/core/artifacts.sh
  source "${REPO_ROOT}/lib/core/artifacts.sh"
}

sha256_of() {
  shasum -a 256 "$1" | awk '{print $1}'
}

write_versions() {
  local checksum="$1"
  printf '%s\n' \
    'release_source: github' \
    'repository: example/demo' \
    'tag_transform:' \
    '  strip_prefix: v' \
    'artifacts:' \
    '  - os: linux' \
    '    architecture: amd64' \
    '    filename: demo-{version}.linux-{architecture}.tar.gz' \
    "    checksum: sha256:${checksum}" \
    'images:' \
    '  - name: demo' \
    '    repository: registry.example/demo' \
    'compatibility:' \
    '  - version: 1.2.0' \
    '    modes: [native, compose]' \
    > "${MH_COMPONENTS_DIR}/demo/versions.yaml"
}

assert_state_is_empty() {
  run find "${MH_STATE_DIR}" -type f -print
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an explicit compatible local package wins" {
  local package="${MH_PACKAGES_DIR}/demo-1.1.0.linux-amd64.tar.gz"
  printf 'release payload\n' > "${package}"
  write_versions "$(sha256_of "${package}")"

  mh_resolve_artifact demo 1.1.0 linux amd64

  [ "${MH_ARTIFACT_VERSION}" = "1.1.0" ]
  [ "${MH_ARTIFACT_PATH}" = "${package}" ]
  [ "${MH_ARTIFACT_SOURCE}" = "packages" ]
}

@test "automatic local selection chooses the highest stable package" {
  printf 'same payload\n' > "${MH_PACKAGES_DIR}/demo-1.1.0.linux-amd64.tar.gz"
  printf 'same payload\n' > "${MH_PACKAGES_DIR}/demo-1.2.0.linux-amd64.tar.gz"
  write_versions "$(sha256_of "${MH_PACKAGES_DIR}/demo-1.2.0.linux-amd64.tar.gz")"

  mh_resolve_artifact demo latest linux amd64

  [ "${MH_ARTIFACT_VERSION}" = "1.2.0" ]
  [ "${MH_ARTIFACT_SOURCE}" = "packages" ]
}

@test "runtime cache is used before the network" {
  mkdir -p "${MH_CACHE_DIR}/artifacts"
  local cached="${MH_CACHE_DIR}/artifacts/demo-1.2.0.linux-amd64.tar.gz"
  printf 'cached payload\n' > "${cached}"
  write_versions "$(sha256_of "${cached}")"

  mh_resolve_artifact demo latest linux amd64

  [ "${MH_ARTIFACT_PATH}" = "${cached}" ]
  [ "${MH_ARTIFACT_SOURCE}" = "cache" ]
}

@test "online resolution records the latest stable version and excludes prereleases" {
  MH_GITHUB_RELEASES_FILE="${FIXTURES}/stable-and-prerelease.json"
  MH_DOWNLOAD_SOURCE_DIR="${BATS_TEST_TMPDIR}/download-source"
  mkdir -p "${MH_DOWNLOAD_SOURCE_DIR}"
  local source_package="${MH_DOWNLOAD_SOURCE_DIR}/demo-1.2.0.linux-amd64.tar.gz"
  printf 'download payload\n' > "${source_package}"
  write_versions "$(sha256_of "${source_package}")"
  export MH_GITHUB_RELEASES_FILE MH_DOWNLOAD_SOURCE_DIR

  mh_resolve_artifact demo latest linux amd64

  [ "${MH_ARTIFACT_VERSION}" = "1.2.0" ]
  [ "${MH_ARTIFACT_SOURCE}" = "network" ]
  [ -f "${MH_ARTIFACT_PATH}" ]
}

@test "an unsupported CPU architecture fails without writing state" {
  write_versions "$(printf 'unused' | shasum -a 256 | awk '{print $1}')"

  run mh_resolve_artifact demo latest linux arm64

  [ "$status" -ne 0 ]
  [[ "$output" == *"no compatible artifact"* ]]
  assert_state_is_empty
}

@test "a checksum mismatch fails without writing state" {
  printf 'tampered\n' > "${MH_PACKAGES_DIR}/demo-1.2.0.linux-amd64.tar.gz"
  write_versions "$(printf 'expected' | shasum -a 256 | awk '{print $1}')"

  run mh_resolve_artifact demo 1.2.0 linux amd64

  [ "$status" -ne 0 ]
  [[ "$output" == *"checksum mismatch"* ]]
  assert_state_is_empty
}

@test "GitHub rate limiting is diagnosed without writing state" {
  MH_GITHUB_RELEASES_FILE="${FIXTURES}/rate-limit.json"
  export MH_GITHUB_RELEASES_FILE

  run mh_github_latest_stable example/demo v

  [ "$status" -ne 0 ]
  [[ "$output" == *"rate limit"* ]]
  assert_state_is_empty
}

@test "network timeout reports the URL and a retry command" {
  local fake_curl="${BATS_TEST_TMPDIR}/curl"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 28' > "${fake_curl}"
  chmod +x "${fake_curl}"
  unset MH_GITHUB_RELEASES_FILE
  MH_CURL_BIN="${fake_curl}"
  export MH_CURL_BIN

  run mh_github_latest_stable example/demo v

  [ "$status" -ne 0 ]
  [[ "$output" == *"https://api.github.com/repos/example/demo/releases"* ]]
  [[ "$output" == *"retry"* ]]
  assert_state_is_empty
}

@test "a matching local image is inspected without pulling latest" {
  write_versions "$(printf 'unused' | shasum -a 256 | awk '{print $1}')"
  local fake_docker="${BATS_TEST_TMPDIR}/docker"
  export MH_DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\\n" "$*" >> "${MH_DOCKER_LOG}"' \
    'if [[ "$1 $2" == "image inspect" ]]; then' \
    '  printf "%s\\n" "registry.example/demo@sha256:0123456789abcdef"' \
    '  exit 0' \
    'fi' \
    'exit 1' \
    > "${fake_docker}"
  chmod +x "${fake_docker}"
  MH_DOCKER_BIN="${fake_docker}"
  export MH_DOCKER_BIN

  mh_resolve_image demo 1.2.0

  [ "${MH_IMAGE_REFERENCE}" = "registry.example/demo:1.2.0" ]
  [ "${MH_IMAGE_DIGEST}" = "registry.example/demo@sha256:0123456789abcdef" ]
  run grep -F 'pull' "${MH_DOCKER_LOG}"
  [ "$status" -ne 0 ]
}

@test "latest image selection uses the highest local stable tag before GitHub" {
  write_versions "$(printf 'unused' | shasum -a 256 | awk '{print $1}')"
  local fake_docker="${BATS_TEST_TMPDIR}/docker"
  export MH_DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\n" "$*" >> "${MH_DOCKER_LOG}"' \
    'if [[ "$1 $2" == "image ls" ]]; then printf "%s\n" "1.2.0" "1.3.0-rc.1" "1.1.0"; exit 0; fi' \
    'if [[ "$1 $2" == "image inspect" ]]; then printf "%s\n" "registry.example/demo@sha256:0123456789abcdef"; exit 0; fi' \
    'exit 1' > "${fake_docker}"
  chmod +x "${fake_docker}"
  export MH_DOCKER_BIN="${fake_docker}"
  unset MH_GITHUB_RELEASES_FILE

  mh_resolve_image demo latest

  [ "${MH_IMAGE_VERSION}" = "1.2.0" ]
  [ "${MH_IMAGE_REFERENCE}" = "registry.example/demo:1.2.0" ]
  run grep -F 'pull' "${MH_DOCKER_LOG}"
  [ "$status" -ne 0 ]
}

@test "configured exact tag resolves to an immutable digest" {
  local fake_docker="${BATS_TEST_TMPDIR}/docker"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "$1 $2" == "image inspect" ]]; then printf "%s\n" "registry.example/demo@sha256:abcdef"; exit 0; fi' \
    'exit 1' > "${fake_docker}"
  chmod +x "${fake_docker}"
  export MH_DOCKER_BIN="${fake_docker}"

  mh_resolve_image_reference registry.example/demo:1.2.0

  [ "${MH_RESOLVED_IMAGE}" = "registry.example/demo@sha256:abcdef" ]
}

@test "image dry-run resolves an exact version without pulling" {
  write_versions "$(printf 'unused' | shasum -a 256 | awk '{print $1}')"
  export MH_GITHUB_RELEASES_FILE="${FIXTURES}/stable-and-prerelease.json"
  export MH_DRY_RUN=1
  export MH_DOCKER_LOG="${BATS_TEST_TMPDIR}/docker.log"
  local fake_docker="${BATS_TEST_TMPDIR}/docker"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >> "${MH_DOCKER_LOG}"' 'exit 1' > "${fake_docker}"
  chmod +x "${fake_docker}"
  export MH_DOCKER_BIN="${fake_docker}"

  mh_resolve_image demo latest

  [ "${MH_IMAGE_REFERENCE}" = "registry.example/demo:1.2.0" ]
  [ -z "${MH_IMAGE_DIGEST}" ]
  [ ! -e "${MH_DOCKER_LOG}" ]
}

@test "image metadata can preserve an upstream tag prefix" {
  write_versions "$(printf 'unused' | shasum -a 256 | awk '{print $1}')"
  sed -i.bak '/compatibility:/i\
    tag_prefix: v\
' "${MH_COMPONENTS_DIR}/demo/versions.yaml"
  rm -f "${MH_COMPONENTS_DIR}/demo/versions.yaml.bak"
  export MH_DRY_RUN=1

  mh_resolve_image demo 1.2.0

  [ "${MH_IMAGE_REFERENCE}" = "registry.example/demo:v1.2.0" ]
}
