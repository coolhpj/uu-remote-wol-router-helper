#!/bin/sh
# Experimental, source-only NetEase UU Docker installer.
# Never runs as an elevated shell, changes host networking, or deletes volumes.
set -eu

REPO="https://github.com/coolhpj/uu-remote-wol-router-helper.git"
BRANCH="feat/docker-experimental"

say() { printf '%s\n' "$*"; }
die() { printf '%s\n' "ERROR: $*" >&2; exit 1; }
usage() {
    say "网易 UU 通用 Docker 实验版 · 一条命令部署"
    say "Usage: sh uu-docker-start.sh [--check|--help]"
    say "Default directory: \$HOME/uu-remote-wol-docker"
    say "Override by setting UU_DOCKER_INSTALL_DIR to an absolute directory path."
    say "No sudo, privileged, host firewall edits, or Docker volume removal."
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    ""|--check) ;;
    *) usage; die "Unknown argument: $1" ;;
esac

[ "$(uname -s)" = Linux ] || die "This installer runs on Linux Docker hosts only."
case "$(uname -m)" in
    x86_64|aarch64|arm64) ;;
    *) die "Unsupported CPU. Currently x86_64 and ARM64 are candidates." ;;
esac
for executable in git docker; do
    command -v "$executable" >/dev/null 2>&1 ||
        die "Missing $executable. Install it using your operating system's official instructions."
done
docker compose version >/dev/null 2>&1 ||
    die "Docker Compose plugin missing. 'docker compose version' must work."
docker info >/dev/null 2>&1 ||
    die "Cannot access Docker Engine. Check that it is running and your user has permission; this installer will not use sudo."

[ -n "${HOME:-}" ] && [ -d "$HOME" ] ||
    die "HOME must reference an existing user directory."
DEST="${UU_DOCKER_INSTALL_DIR:-$HOME/uu-remote-wol-docker}"
case "$DEST" in
    /*) ;;
    *) die "UU_DOCKER_INSTALL_DIR must be absolute." ;;
esac
[ ! -L "$DEST" ] || die "Refusing symlink installation directory."
if [ -e "$DEST" ]; then
    [ -d "$DEST/.git" ] || die "Directory exists and is not the expected Git checkout: $DEST"
    remote="$(git -C "$DEST" remote get-url origin 2>/dev/null || true)"
    [ "$remote" = "$REPO" ] || die "Existing directory has another Git remote; refusing to overwrite."
    current_branch="$(git -C "$DEST" symbolic-ref --short HEAD 2>/dev/null || true)"
    [ "$current_branch" = "$BRANCH" ] ||
        die "Existing directory is not on the Docker experimental branch."
    [ -z "$(git -C "$DEST" status --porcelain)" ] ||
        die "Existing checkout has uncommitted changes; refusing to overwrite."
    [ -f "$DEST/compose.yaml" ] && [ -f "$DEST/Dockerfile" ] ||
        die "Existing checkout is incomplete."
    say "Found existing experimental checkout; reusing without git pull or deleting data."
else
    [ -d "$(dirname "$DEST")" ] ||
        die "The parent directory does not exist: $(dirname "$DEST")"
    say "Cloning the Docker experimental branch (not main)..."
    git clone --depth 1 --single-branch --branch "$BRANCH" "$REPO" "$DEST" ||
        die "Git clone failed. Check the directory before retrying."
fi

say "Checking source configuration; no host firewall or network settings will be changed."
(
    cd "$DEST"
    docker compose config --quiet
) || die "Compose validation failed."

if [ "${1:-}" = "--check" ]; then
    say "DOCKER_QUICKSTART_PREFLIGHT_OK; no image built and no container started."
    exit 0
fi

say "Experimental only. This uses host networking and a persistent identity volume."
say "Confirm no other UU service is using the same identity or conflicting ports."
say "Building source-only Docker image and starting the UU helper..."
(
    cd "$DEST"
    docker compose build
    docker compose up -d --no-build
    docker compose ps
) || die "Docker deployment did not complete. The source/data volume was not deleted."

say ""
say "DOCKER_QUICKSTART_SUBMITTED"
say "Open NetEase UU on your phone while connected to home Wi-Fi to try binding."
say "Then turn OFF Wi-Fi and use mobile data to test waking up a powered-off PC."
say "No real remote WOL success can be inferred from the container being online."
say "Project directory: $DEST"
say "Status: cd '$DEST' && docker compose ps"
say "Stop:   cd '$DEST' && docker compose stop"
say "Remove containers but KEEP binding data: cd '$DEST' && docker compose down"
say "NEVER run 'docker compose down -v' unless you deliberately intend to destroy identity data."
