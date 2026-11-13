#!/bin/sh
# Read-only preflight for the NAS / Linux Docker router-identity beta.
# Never alters firewall, containers, volumes, SSH or NAS configuration.
set -eu
if [ "${1:-}" = "--help" ]; then
  printf '%s\n' 'Usage: sh scripts/nas-preflight.sh' \
    'Checks only. No installation, cloud login, binding or WOL packet.'
  exit 0
fi
[ "$#" -eq 0 ] || { printf '%s\n' 'ERROR unsupported argument' >&2; exit 2; }
failed=0
check() {
  label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s\n' "$label"
    failed=1
  fi
}
is_linux() { [ "$(uname -s)" = "Linux" ]; }
supported_arch() {
  case "$(uname -m)" in x86_64|aarch64|arm64) return 0 ;; *) return 1 ;; esac
}
has_git() { command -v git >/dev/null 2>&1; }
has_curl() { command -v curl >/dev/null 2>&1; }
docker_daemon() { docker info >/dev/null 2>&1; }
compose_plugin() { docker compose version >/dev/null 2>&1; }
check 'Linux host' is_linux
check 'x86_64 or ARM64 CPU' supported_arch
check 'Git' has_git
check 'curl' has_curl
check 'Docker CLI' command -v docker
if command -v docker >/dev/null 2>&1; then
  check 'Docker Engine accessible (no sudo)' docker_daemon
  check 'docker compose plugin' compose_plugin
fi
if [ -n "${DOCKER_HOST:-}" ]; then
  printf '%s\n' 'WARN DOCKER_HOST is set: inspect which host will receive this deployment.'
fi
printf '%s\n' 'NOTE beta uses Docker HOST networking; check for an existing UU process or port conflict yourself.'
printf '%s\n' 'NOTE this only checks prerequisites; it does not prove cloud binding or remote wake.'
if [ "$failed" -ne 0 ]; then
  printf '%s\n' 'NAS_PREFLIGHT_FAILED: do not run the installer until prerequisites are fixed.'
  exit 1
fi
printf '%s\n' 'NAS_PREFLIGHT_OK: review the Docker beta security guide before deployment.'
