#!/bin/sh
# Source-only Docker adapter. Reuse existing validated NetEase stage path.
set -eu

APP=/opt/uu-helper
DATA=/var/lib/uu-wol
RUNTIME="$DATA/runtime"
STAGE=/tmp/uu-wol-helper-docker-stage

. "$APP/lib/channel.sh"

die() { printf '%s\n' "$*" >&2; exit 1; }

channel_for_arch() {
    arch=$(uname -m)
    # Uses the same reviewed mapping as native OpenWrt; unknown fails closed.
    channel=$(uu_resolve_channel openwrt "$arch") || die "Unsupported Docker CPU architecture: $arch"
    case "$channel" in
        openwrt-x86_64|openwrt-aarch64) printf '%s\n' "$channel" ;;
        *) die "Unsupported Docker official package channel: $channel" ;;
    esac
}

check_data() {
    [ -d "$DATA" ] && [ ! -L "$DATA" ] && [ -w "$DATA" ] ||
        die "Persistent /var/lib/uu-wol volume is missing, symlinked, or not writable"
    [ ! -L "$RUNTIME" ] || die "Unsafe runtime symlink"
    [ ! -e "$RUNTIME" ] || [ -d "$RUNTIME" ] || die "Runtime path is not a directory"
}

lock_data() {
    # The descriptor survives exec; competing start/refresh fails closed.
    [ ! -L "$DATA/.runtime.lock" ] || die "Unsafe lock symlink"
    ( umask 077; : > "$DATA/.runtime.lock" )
    exec 9>"$DATA/.runtime.lock"
    flock -n 9 || die "UU runtime already using the persistent volume"
}

stage_official() {
    channel=$(channel_for_arch)
    UU_STAGE_DIR="$STAGE" sh "$APP/scripts/stage-package.sh" "$channel" ||
        die "Official plugin staging/verification failed; refusing to run"
    [ -d "$STAGE/files" ] && [ ! -L "$STAGE/files" ] || die "Unsafe staged files directory"
    # Reject even non-required symlinks before copying files from the archive.
    if find "$STAGE/files" -type l | grep -q .; then
        die "Official package contains symlinks; refusing Docker installation"
    fi
    for name in uuplugin xuplugin-guardian uu.conf xtables-nft-multi; do
        [ -f "$STAGE/files/$name" ] && [ ! -L "$STAGE/files/$name" ] ||
            die "Official package member missing or unsafe: $name"
    done
    [ -x "$STAGE/files/uuplugin" ] || die "Official uuplugin is not executable"
}

install_official() {
    # Called only while holding the exclusive runtime lock.
    stage_official
    [ -d "$RUNTIME" ] || ( umask 077; mkdir "$RUNTIME" ) || die "Cannot create runtime"
    [ ! -L "$RUNTIME" ] || die "Unsafe runtime symlink"

    # Never replace binding state (.uuplugin_uuid), account state, or existing
    # uu.conf. Upgrading a source image never wipes this persistent directory.
    # Keep verified binaries in the stable working directory required by UU.
    for name in uuplugin xuplugin-guardian xtables-nft-multi uu.conf; do
        [ ! -L "$RUNTIME/$name" ] || die "Unsafe persistent file symlink: $name"
        if [ "$name" = uu.conf ] && [ -f "$RUNTIME/uu.conf" ]; then
            continue
        fi
        cp "$STAGE/files/$name" "$RUNTIME/.$name.next.$$" ||
            die "Unable to copy verified file: $name"
        if [ "$name" != uu.conf ]; then
            chmod 700 "$RUNTIME/.$name.next.$$"
        else
            chmod 600 "$RUNTIME/.$name.next.$$"
        fi
        mv -f "$RUNTIME/.$name.next.$$" "$RUNTIME/$name" ||
            die "Unable to activate verified file: $name"
    done
    # This is a local provenance hint, not proof of remote cloud or WOL success.
    cp "$STAGE/metadata" "$DATA/.official-package-metadata" ||
        die "Unable to store official package metadata"
    chmod 600 "$DATA/.official-package-metadata"
    echo "DOCKER_OFFICIAL_STAGE_INSTALLED"
}

check_runtime() {
    [ -f "$RUNTIME/uuplugin" ] && [ -x "$RUNTIME/uuplugin" ] &&
    [ -f "$RUNTIME/uu.conf" ] && [ ! -L "$RUNTIME/uuplugin" ] &&
    [ ! -L "$RUNTIME/uu.conf" ] || die "Verified runtime missing; stop before restart"
}

smoke() {
    # Test-only: no NetEase API, no official binary, no UU cloud, no WOL.
    check_data
    ( umask 077; printf 'docker-smoke-v1\n' > "$DATA/.docker-smoke" )
    [ "$(cat "$DATA/.docker-smoke")" = docker-smoke-v1 ] || die "Smoke marker failed"
    echo "DOCKER_CONTAINER_SMOKE_OK (not official plugin)"
}

check_persistence() {
    check_data
    [ -f "$DATA/.docker-smoke" ] &&
    [ "$(cat "$DATA/.docker-smoke")" = docker-smoke-v1 ] ||
        die "Persisted smoke marker missing"
    echo "DOCKER_PERSISTENCE_OK (not official plugin)"
}

# Ephemeral CI diagnostic: deliberately does not use the persistent data volume.
# The container must be started with a private Docker bridge and no NET_ADMIN.
# No raw official runtime logs (which may contain identity material) are printed.
probe_runtime() {
    stage_official
    cd "$STAGE/files" || die "Cannot enter probe directory"
    ( umask 077; : > "$STAGE/probe.log" )
    ./uuplugin ./uu.conf > "$STAGE/probe.log" 2>&1 &
    probe_pid=$!
    seen_alive=no
    seen_cloud_port=no
    count=0
    while [ "$count" -lt 10 ]; do
        sleep 2
        if ! kill -0 "$probe_pid" 2>/dev/null; then
            break
        fi
        seen_alive=yes
        # In the private container network namespace only. TCP state 01
        # = ESTABLISHED, remote port 0x3E80 = 16000. Not proof of UU identity.
        if awk 'FNR > 1 && $4 == "01" && $3 ~ /:3[Ee]80$/ {found=1} END {exit !found}' \
            /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
            seen_cloud_port=yes
        fi
        count=$((count + 1))
    done
    kill "$probe_pid" 2>/dev/null || true
    wait "$probe_pid" 2>/dev/null || true
    printf 'UU_DOCKER_PROBE_PROCESS_ALIVE=%s\n' "$seen_alive"
    printf 'UU_DOCKER_PROBE_PORT16000_ESTABLISHED=%s\n' "$seen_cloud_port"
    if [ "$seen_alive" != yes ]; then
        if grep -Eiq 'not found|error loading shared library|symbol not found|no such file|exec format' \
            "$STAGE/probe.log"; then
            echo "UU_DOCKER_PROBE_DIAG=possible_elf_loader_or_dependency_problem"
        else
            echo "UU_DOCKER_PROBE_DIAG=process_exited_early_see_private_runner_logs"
        fi
        return 1
    fi
    [ "$seen_cloud_port" = yes ] || {
        echo "UU_DOCKER_PROBE_DIAG=no_observed_tcp_16000_connection"
        return 1
    }
    echo "UU_DOCKER_PROBE_READY_IN_ISOLATED_BRIDGE (not proof of real WOL)"
}

cmd="${1:-run}"
case "$cmd" in
    smoke) smoke ;;
    probe-runtime) probe_runtime ;;
    stage-only)
        stage_official
        echo "DOCKER_OFFICIAL_STAGE_ONLY_OK (plugin not executed)"
        ;;
    persistence-check) check_persistence ;;
    status)
        check_data
        channel_for_arch
        if [ -x "$RUNTIME/uuplugin" ]; then
            echo "docker_runtime_files: present (not a UU cloud/WOL check)"
        else
            echo "docker_runtime_files: absent"
        fi
        ;;
    run)
        check_data
        lock_data
        if [ ! -x "$RUNTIME/uuplugin" ]; then
            install_official
        fi
        check_runtime
        cd "$RUNTIME" || die "Cannot enter persistent runtime"
        echo "DOCKER_RUNTIME_EXEC_ATTEMPT (UU cloud/WOL not verified)"
        exec ./uuplugin ./uu.conf
        ;;
    refresh)
        # Run only after docker compose stop; flock prevents concurrent writer.
        check_data
        lock_data
        install_official
        echo "DOCKER_OFFICIAL_REFRESH_DONE (identity directory preserved)"
        ;;
    *)
        die "Usage: run | refresh | stage-only | probe-runtime | status | smoke | persistence-check"
        ;;
esac
