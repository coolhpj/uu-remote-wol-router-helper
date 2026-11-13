#!/usr/bin/env bash
# CI-only real UU identity persistence test. Uses an ephemeral named volume.
# No preexisting UU identities, host networking, firewall changes, or registry pushes.
set -euo pipefail

image="${1:-uu-docker-experimental:test}"
vol="uu-real-identity-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-${RANDOM}"
private_logs="$(mktemp -d)"
cleanup() {
    docker volume rm "$vol" >/dev/null 2>&1 || true
    rm -rf -- "$private_logs"
}
trap cleanup EXIT
docker volume create "$vol" >/dev/null

run_plugin() {
    local phase="$1"
    if ! timeout 110s docker run --rm --init --network bridge \
        --cap-drop ALL --cap-add NET_RAW --security-opt no-new-privileges \
        --read-only --tmpfs /tmp:rw,nosuid,nodev,size=64m \
        --tmpfs /run:rw,nosuid,nodev,noexec,size=8m,uid=10001,gid=10001,mode=0700 \
        --user 10001:10001 -v "$vol:/var/lib/uu-wol" \
        "$image" probe-runtime >"$private_logs/$phase.log" 2>&1; then
        printf 'UU_REAL_IDENTITY_%s_PLUGIN_RUNTIME=fail\n' "$phase" >&2
        return 1
    fi
    # The plugin, guardian, and TCP connection must all be observed;
    # these are not a claim that a real PC has been powered on.
    for marker in \
        'UU_DOCKER_PROBE_PROCESS_LAST_SAMPLE=yes' \
        'UU_DOCKER_PROBE_GUARDIAN_LAST_SAMPLE=yes' \
        'UU_DOCKER_PROBE_PORT16000_ESTABLISHED=yes' \
        'UU_DOCKER_UUID_FILE_NONEMPTY=yes' \
        'UU_DOCKER_SN_FILE_NONEMPTY=yes'; do
        if ! grep -Fxq "$marker" "$private_logs/$phase.log"; then
            printf 'UU_REAL_IDENTITY_%s_RUNTIME_MARKER_MISSING\n' "$phase" >&2
            return 1
        fi
    done
    printf 'UU_REAL_IDENTITY_%s_RUNTIME_AND_CLOUD_PORT=pass\n' "$phase"
}

identity_fingerprints() {
    # Hashes stay only in shell memory. Do not print, upload or log identity.
    docker run --rm --network none --cap-drop ALL --read-only \
        --user 10001:10001 -v "$vol:/var/lib/uu-wol:ro" \
        --entrypoint /bin/sh "$image" -c '
            set -eu
            cd /var/lib/uu-wol/runtime
            for f in .uuplugin_uuid .sn; do
                test -f "$f" && test -s "$f" && test ! -L "$f"
            done
            sha256sum .uuplugin_uuid .sn
        '
}

echo 'UU_REAL_IDENTITY_VOLUME=fresh_ephemeral'
run_plugin first
before="$(identity_fingerprints)"
[ -n "$before" ] || { echo 'UU_REAL_IDENTITY_INITIAL=missing' >&2; exit 1; }
echo 'UU_REAL_IDENTITY_INITIAL_GENERATION=pass'

# Emulate updating the official plugin while the earlier container is gone.
if ! timeout 110s docker run --rm --network bridge \
    --cap-drop ALL --security-opt no-new-privileges --read-only \
    --tmpfs /tmp:rw,nosuid,nodev,size=64m \
    --tmpfs /run:rw,nosuid,nodev,noexec,size=8m,uid=10001,gid=10001,mode=0700 \
    --user 10001:10001 -v "$vol:/var/lib/uu-wol" \
    "$image" refresh >"$private_logs/refresh.log" 2>&1; then
    echo 'UU_REAL_IDENTITY_REFRESH=fail' >&2
    exit 1
fi
after_refresh="$(identity_fingerprints)"
[ "$before" = "$after_refresh" ] || {
    echo 'UU_REAL_IDENTITY_AFTER_REFRESH=changed' >&2
    exit 1
}
echo 'UU_REAL_IDENTITY_AFTER_REFRESH=preserved'

# Recreate a new container against the exact same named data volume.
# /run remains ephemeral and is reconstructed from scratch on every run.
run_plugin recreate
after_recreate="$(identity_fingerprints)"
[ "$before" = "$after_recreate" ] || {
    echo 'UU_REAL_IDENTITY_AFTER_RECREATE=changed' >&2
    exit 1
}
echo 'UU_REAL_IDENTITY_AFTER_RECREATE=preserved'
echo 'UU_REAL_IDENTITY_VOL_TEST=pass (does not verify account binding or WOL)'

docker volume rm "$vol" >/dev/null
if docker volume inspect "$vol" >/dev/null 2>&1; then
    echo 'UU_REAL_IDENTITY_CLEANUP=fail' >&2
    exit 1
fi
echo 'UU_REAL_IDENTITY_CLEANUP=pass'
