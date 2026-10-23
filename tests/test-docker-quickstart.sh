#!/bin/sh
# Offline contract test with fake Git and Docker. No real clone, build or service.
set -eu

SCRIPT="${1:-docker/quickstart.sh}"
[ -f "$SCRIPT" ] || { echo "quickstart script missing" >&2; exit 1; }
sh -n "$SCRIPT"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/bin" "$tmp/home"
cat > "$tmp/bin/git" <<'MOCK_GIT'
#!/bin/sh
set -eu
printf 'git %s\n' "$*" >> "$MOCK_ACTIONS"
case "$1" in
    clone)
        for argument do :; done
        dir="$argument"
        mkdir -p "$dir/.git"
        : > "$dir/compose.yaml"
        : > "$dir/Dockerfile"
        ;;
    -C)
        shift 2
        case "$1 ${2:-} ${3:-}" in
            "remote get-url origin") printf '%s\n' 'https://github.com/coolhpj/uu-remote-wol-router-helper.git' ;;
            "symbolic-ref --short HEAD") printf '%s\n' 'feat/docker-experimental' ;;
            "status --porcelain ") ;;
            *) echo "Unexpected fake git call: $*" >&2; exit 1 ;;
        esac
        ;;
    *) echo "Unexpected fake git call: $*" >&2; exit 1 ;;
esac
MOCK_GIT
cat > "$tmp/bin/docker" <<'MOCK_DOCKER'
#!/bin/sh
set -eu
printf 'docker %s\n' "$*" >> "$MOCK_ACTIONS"
case "$1" in
    info) [ "${MOCK_DOCKER_DENY:-0}" != 1 ] ;;
    compose)
        case "${2:-}" in
            version|config|build|up|ps) ;;
            *) echo "Unsafe/unknown fake docker call: $*" >&2; exit 1 ;;
        esac
        ;;
    *) echo "Unexpected fake docker call: $*" >&2; exit 1 ;;
esac
MOCK_DOCKER
chmod 755 "$tmp/bin/git" "$tmp/bin/docker"
export HOME="$tmp/home" MOCK_ACTIONS="$tmp/actions"
export UU_DOCKER_INSTALL_DIR="$HOME/uu-remote-wol-docker"
PATH="$tmp/bin:$PATH"
export PATH

sh "$SCRIPT" --help >/dev/null
sh "$SCRIPT" --check >/dev/null
[ -d "$UU_DOCKER_INSTALL_DIR/.git" ]
if grep -qE '^docker compose (build|up)' "$MOCK_ACTIONS"; then
    echo "CHECK unexpectedly built or started containers" >&2; exit 1
fi

sh "$SCRIPT" >/dev/null
[ "$(grep -c '^git clone ' "$MOCK_ACTIONS")" -eq 1 ]
[ "$(grep -c '^docker compose build' "$MOCK_ACTIONS")" -eq 1 ]
[ "$(grep -c '^docker compose up ' "$MOCK_ACTIONS")" -eq 1 ]
[ "$(grep -c '^docker compose ps' "$MOCK_ACTIONS")" -eq 1 ]
if grep -Eq '(^docker compose down|docker.*privileged|docker.*NET_ADMIN|git.*reset)' "$MOCK_ACTIONS"; then
    echo "Unsafe command in quickstart test" >&2; exit 1
fi

# Repeat launch should preserve existing checkout and never clone over it.
sh "$SCRIPT" >/dev/null
[ "$(grep -c '^git clone ' "$MOCK_ACTIONS")" -eq 1 ]
[ "$(grep -c '^docker compose up ' "$MOCK_ACTIONS")" -eq 2 ]

# Refuse unrelated preexisting directories instead of overwriting user files.
mkdir -p "$HOME/unrelated"
if UU_DOCKER_INSTALL_DIR="$HOME/unrelated" sh "$SCRIPT" --check >/dev/null 2>&1; then
    echo "Existing unrelated directory was not rejected" >&2; exit 1
fi
# Refuse when current user has no access to the Docker daemon.
if MOCK_DOCKER_DENY=1 sh "$SCRIPT" --check >/dev/null 2>&1; then
    echo "Unavailable Docker daemon was not rejected" >&2; exit 1
fi

echo "DOCKER_QUICKSTART_OFFLINE_TEST_PASS"
