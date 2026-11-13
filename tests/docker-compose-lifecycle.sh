#!/usr/bin/env bash
# Real Compose lifecycle test only on an isolated GitHub-hosted Linux runner.
# No real user volume or device identity is mounted, and no registry is used.
set -euo pipefail
image="uu-remote-wol-helper:docker-experimental"
project="uucomposeci${GITHUB_RUN_ID:-0}a${GITHUB_RUN_ATTEMPT:-1}"
volume="${project}_uu_wol_data"
created=no

cleanup() {
    docker compose -p "$project" down >/dev/null 2>&1 || true
    if [ "$created" = yes ]; then
        docker volume rm "$volume" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

# Only a unique CI project may be deleted by the cleanup handler.
if docker volume inspect "$volume" >/dev/null 2>&1; then
    echo 'UU_COMPOSE_CI_UNSAFE_EXISTING_VOLUME' >&2
    exit 1
fi
docker tag uu-docker-experimental:test "$image"
docker compose -p "$project" up -d --no-build
created=yes

container_id() {
    docker compose -p "$project" ps -q uu-wol
}
running_guardian_and_plugin() {
    local cid="$1"
    docker exec "$cid" /bin/sh -c '
      for pattern in uuplugin xuplugin-guard; do
          found=no
          for f in /proc/[0-9]*/comm; do
              [ -r "$f" ] || continue
              IFS= read -r comm < "$f" || continue
              case "$comm" in
                  "$pattern"*) found=yes ;;
              esac
          done
          [ "$found" = yes ] || exit 1
      done
      test -s /var/lib/uu-wol/runtime/.uuplugin_uuid
      test -s /var/lib/uu-wol/runtime/.sn
      awk '\''FNR>1 && $4=="01" && $3 ~ /:3[Ee]80$/ {seen=1} END {exit !seen}'\'' /proc/net/tcp /proc/net/tcp6
    ' >/dev/null 2>&1
}
await_runtime() {
    local cid="$1"
    local attempt
    for attempt in $(seq 1 20); do
        if [ "$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null || true)" = true ] && running_guardian_and_plugin "$cid"; then
            return 0
        fi
        sleep 2
    done
    return 1
}
identity_fingerprints() {
    local cid="$1"
    docker exec "$cid" /bin/sh -c '
      set -eu
      cd /var/lib/uu-wol/runtime
      for f in .uuplugin_uuid .sn; do
          test -f "$f" && test -s "$f" && test ! -L "$f"
      done
      sha256sum .uuplugin_uuid .sn
    '
}

cid="$(container_id)"
[ -n "$cid" ] || { echo 'UU_COMPOSE_START=no_container' >&2; exit 1; }
[ "$(docker inspect -f '{{.HostConfig.Privileged}}' "$cid")" = false ] ||
    { echo 'UU_COMPOSE_SECURITY=privileged' >&2; exit 1; }
[ "$(docker inspect -f '{{.HostConfig.NetworkMode}}' "$cid")" = host ] ||
    { echo 'UU_COMPOSE_NETWORK=not_host' >&2; exit 1; }
[ "$(docker inspect -f '{{.HostConfig.ReadonlyRootfs}}' "$cid")" = true ] ||
    { echo 'UU_COMPOSE_SECURITY=root_filesystem_writable' >&2; exit 1; }
case "$(docker inspect -f '{{json .HostConfig.CapAdd}}' "$cid")" in
    *NET_ADMIN*) echo 'UU_COMPOSE_SECURITY=network_administration_granted' >&2; exit 1 ;;
esac
await_runtime "$cid" || { echo 'UU_COMPOSE_FIRST_RUNTIME=not_ready' >&2; exit 1; }
before="$(identity_fingerprints "$cid")"
[ -n "$before" ] || exit 1
echo 'UU_COMPOSE_REAL_RUNTIME_WITH_HOST_NETWORK=pass'

docker compose -p "$project" stop
[ "$(docker inspect -f '{{.State.Running}}' "$cid")" = false ] ||
    { echo 'UU_COMPOSE_STOP=container_still_running' >&2; exit 1; }
echo 'UU_COMPOSE_STOP=pass'

docker compose -p "$project" up -d --no-build --force-recreate
cid_after="$(container_id)"
[ -n "$cid_after" ] && [ "$cid_after" != "$cid" ] ||
    { echo 'UU_COMPOSE_RECREATE=container_not_recreated' >&2; exit 1; }
await_runtime "$cid_after" ||
    { echo 'UU_COMPOSE_RECREATE_RUNTIME=not_ready' >&2; exit 1; }
after="$(identity_fingerprints "$cid_after")"
[ "$before" = "$after" ] || {
    echo 'UU_COMPOSE_RECREATE_IDENTITY=changed' >&2
    exit 1
}
echo 'UU_COMPOSE_RECREATE_RUNTIME_AND_IDENTITY=pass'

# Normal uninstall must preserve the volume and account identity.
docker compose -p "$project" down
docker volume inspect "$volume" >/dev/null 2>&1 || {
    echo 'UU_COMPOSE_DOWN=lost_identity_volume' >&2
    exit 1
}
after_down="$(
    docker run --rm --network none --cap-drop ALL --read-only --user 10001:10001 \
      -v "$volume:/var/lib/uu-wol:ro" --entrypoint /bin/sh "$image" -c '
        cd /var/lib/uu-wol/runtime && sha256sum .uuplugin_uuid .sn'
)"
[ "$before" = "$after_down" ] || {
    echo 'UU_COMPOSE_DOWN_IDENTITY=changed' >&2
    exit 1
}
echo 'UU_COMPOSE_DOWN_PRESERVES_IDENTITY_VOLUME=pass'

# The test created this exact CI-only volume; never use compose down -v
# against user systems or an existing Compose project.
docker volume rm "$volume" >/dev/null
created=no
if docker volume inspect "$volume" >/dev/null 2>&1; then
    echo 'UU_COMPOSE_CI_VOLUME_CLEANUP=failed' >&2
    exit 1
fi
echo 'UU_COMPOSE_CI_VOLUME_CLEANUP=pass'
echo 'UU_COMPOSE_TEST=pass (not real LAN remote WOL)'
