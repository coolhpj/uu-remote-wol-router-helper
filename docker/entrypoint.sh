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

# Ephemeral CI diagnostic: uses only an anonymous Docker data volume, removed
# when the probe container exits. Never mount a user's existing identity volume.
# All probes use a private Docker bridge, never host networking. One CI-only
# comparison grants NET_ADMIN inside that isolated namespace, not the host.
# No raw official runtime logs (which may contain identity material) are printed.
probe_runtime() {
    check_data
    lock_data
    # Use the exact managed installation/working-directory path as production.
    # This prevents false failures from a possible noexec /tmp mount.
    install_official
    check_runtime
    cd "$RUNTIME" || die "Cannot enter managed runtime directory"
    printf '#!/bin/sh\nexit 0\n' > "$RUNTIME/.probe-exec-test"
    chmod 700 "$RUNTIME/.probe-exec-test"
    if "$RUNTIME/.probe-exec-test"; then
        echo "UU_DOCKER_RUNTIME_VOLUME_EXEC=allowed"
    else
        echo "UU_DOCKER_RUNTIME_VOLUME_EXEC=blocked"
    fi
    rm -f "$RUNTIME/.probe-exec-test"
    printf '#!/bin/sh\nexit 0\n' > "$STAGE/.probe-tmp-exec-test"
    chmod 700 "$STAGE/.probe-tmp-exec-test"
    if "$STAGE/.probe-tmp-exec-test" >/dev/null 2>&1; then
        echo "UU_DOCKER_TMP_STAGE_EXEC=allowed"
    else
        echo "UU_DOCKER_TMP_STAGE_EXEC=blocked"
    fi
    rm -f "$STAGE/.probe-tmp-exec-test"
    # scanelf reads ELF metadata without invoking the binary.
    interpreter=$(scanelf -i -F '%i' ./uuplugin 2>/dev/null | head -n 1 | tr -d '[:space:]' || true)
    case "$interpreter" in
        ''|-) echo "UU_DOCKER_ELF_INTERPRETER=static_or_unknown" ;;
        /*)
            if [ -e "$interpreter" ]; then
                echo "UU_DOCKER_ELF_INTERPRETER=present"
            else
                echo "UU_DOCKER_ELF_INTERPRETER=missing"
            fi ;;
        *) echo "UU_DOCKER_ELF_INTERPRETER=unrecognized" ;;
    esac
    needed=$(scanelf -n -F '%n' ./uuplugin 2>/dev/null || true)
    case "$needed" in
        *libc.so.6*) echo "UU_DOCKER_ELF_LIBC=glibc" ;;
        *libc.musl*|*ld-musl*) echo "UU_DOCKER_ELF_LIBC=musl" ;;
        *) echo "UU_DOCKER_ELF_LIBC=static_or_unknown" ;;
    esac

    ( umask 077; : > "$STAGE/probe.log" )
    if [ "${UU_CI_TRACE_SYSCALLS:-0}" = 1 ] && command -v strace >/dev/null 2>&1; then
        # Collect a private ephemeral trace; never print paths, endpoints,
        # process arguments, UUIDs, addresses or original trace lines.
        strace -qq -f -e trace=%file,%network,ioctl -o "$STAGE/probe.strace" \
            ./uuplugin ./uu.conf > "$STAGE/probe.log" 2>&1 &
        echo "UU_DOCKER_TRACE_ATTEMPTED=yes"
    else
        ./uuplugin ./uu.conf > "$STAGE/probe.log" 2>&1 &
        echo "UU_DOCKER_TRACE_ATTEMPTED=no"
    fi
    probe_pid=$!
    seen_plugin=no
    seen_cloud_port=no
    count=0
    while [ "$count" -lt 10 ]; do
        sleep 2
        # The official launcher might daemonize: inspect processes by name
        # rather than treating a short-lived parent as proof of failure.
        for comm_path in /proc/[0-9]*/comm; do
            [ -r "$comm_path" ] || continue
            IFS= read -r comm < "$comm_path" || continue
            [ "$comm" = uuplugin ] && seen_plugin=yes
        done
        # In the container network namespace only: established TCP/16000.
        if awk 'FNR > 1 && $4 == "01" && $3 ~ /:3[Ee]80$/ {found=1} END {exit !found}' \
            /proc/net/tcp /proc/net/tcp6 2>/dev/null; then
            seen_cloud_port=yes
        fi
        if ! kill -0 "$probe_pid" 2>/dev/null && [ "$seen_plugin" = no ]; then
            break
        fi
        count=$((count + 1))
    done
    kill "$probe_pid" 2>/dev/null || true
    if wait "$probe_pid" 2>/dev/null; then
        probe_exit=0
    else
        probe_exit=$?
    fi
    printf 'UU_DOCKER_PROBE_PROCESS_OBSERVED=%s\n' "$seen_plugin"
    printf 'UU_DOCKER_PROBE_PORT16000_ESTABLISHED=%s\n' "$seen_cloud_port"
    printf 'UU_DOCKER_PROBE_LAUNCHER_EXIT=%s\n' "$probe_exit"
    printf 'UU_DOCKER_PROBE_LOG_BYTES=%s\n' "$(wc -c < "$STAGE/probe.log" | tr -d '[:space:]')"
    if [ -s "$STAGE/probe.strace" ]; then
        echo "UU_DOCKER_TRACE_CAPTURED=yes"
        # Emit only aggregated syscall counts; never print trace arguments,
        # paths, IP addresses, account identifiers or original log lines.
        for call in openat newfstatat stat statx access readlink execve connect ioctl; do
            count=$(grep -Ec "$call\(.* = -1 ENOENT" "$STAGE/probe.strace" || true)
            printf 'UU_DOCKER_TRACE_ENOENT_CALL_%s=%s\n' "$call" "$count"
        done
        count=$(grep -c 'connect(.*AF_INET' "$STAGE/probe.strace" || true)
        printf 'UU_DOCKER_TRACE_INET_CONNECT_ATTEMPTS=%s\n' "$count"
        for spec in \
            'OPENWRT_RELEASE:/etc/openwrt_release' \
            'UCI_NETWORK:/etc/config/network' \
            'UCI_SYSTEM:/etc/config/system' \
            'UCI_FIREWALL:/etc/config/firewall' \
            'UBUS_SOCKET:/var/run/ubus.sock' \
            'UUSYSTEM_DIR:/usr/sbin/uu' \
            'UUID_STATE:.uuplugin_uuid' \
            'TUN_DEVICE:/dev/net/tun'; do
            label=$(printf '%s' "$spec" | cut -d: -f1)
            path=$(printf '%s' "$spec" | cut -d: -f2-)
            if grep -F "$path" "$STAGE/probe.strace" | grep -q ENOENT; then
                printf 'UU_DOCKER_TRACE_MISSING_%s=yes\n' "$label"
            fi
        done
        for errno in ENOENT EACCES EPERM EROFS ENETUNREACH ECONNREFUSED EADDRNOTAVAIL EINVAL ENOSYS; do
            count=$(grep -c " = -1 ${errno}" "$STAGE/probe.strace" || true)
            printf 'UU_DOCKER_TRACE_ERRNO_%s=%s\n' "$errno" "$count"
        done
    elif [ "${UU_CI_TRACE_SYSCALLS:-0}" = 1 ]; then
        echo "UU_DOCKER_TRACE_CAPTURED=no"
    fi
    if [ ! -s "$STAGE/probe.log" ]; then
        echo "UU_DOCKER_PROBE_LOG_CLASS=empty"
    elif grep -Eiq 'operation not permitted|permission denied|read-only file system|iptables|netlink|nftables|nft' "$STAGE/probe.log"; then
        echo "UU_DOCKER_PROBE_LOG_CLASS=permission_or_firewall"
    elif grep -Eiq 'not found|error loading shared library|symbol not found|exec format|error relocating' "$STAGE/probe.log"; then
        echo "UU_DOCKER_PROBE_LOG_CLASS=elf_dependency"
    elif grep -Eiq 'openwrt|uci|ubus|router|interface|network' "$STAGE/probe.log"; then
        echo "UU_DOCKER_PROBE_LOG_CLASS=router_environment"
    else
        echo "UU_DOCKER_PROBE_LOG_CLASS=unclassified"
    fi
    # Only emit fixed, public diagnostic vocabulary; never raw UU logs.
    for keyword in error failed fail init unsupported invalid usage config device router cloud network interface gateway mac uuid uci ubus firewall iptables nft netlink address login license register bind startup openwrt version permission busybox; do
        if grep -Eiq "(^|[^[:alnum:]_])${keyword}([^[:alnum:]_]|$)" "$STAGE/probe.log"; then
            printf 'UU_DOCKER_PROBE_LOG_KEYWORD_%s=yes\n' "$keyword"
        fi
    done
    if grep -Eq '错误|失败|无法|初始化|路由|网关|绑定' "$STAGE/probe.log"; then
        echo "UU_DOCKER_PROBE_LOG_HAS_CHINESE_ERROR_TERMS=yes"
    fi
    if grep -Eiq 'not found|error loading shared library|symbol not found|no such file|exec format|error relocating' "$STAGE/probe.log"; then
        echo "UU_DOCKER_PROBE_DIAG=possible_elf_loader_or_dependency_problem"
    elif grep -Eiq 'operation not permitted|permission denied|read-only file system|iptables|netlink|nftables' "$STAGE/probe.log"; then
        echo "UU_DOCKER_PROBE_DIAG=possible_namespace_or_permission_problem"
    elif [ "$seen_plugin" != yes ]; then
        echo "UU_DOCKER_PROBE_DIAG=plugin_not_running"
    elif [ "$seen_cloud_port" != yes ]; then
        echo "UU_DOCKER_PROBE_DIAG=no_observed_tcp_16000_connection"
    else
        echo "UU_DOCKER_PROBE_DIAG=no_obvious_error"
    fi
    [ "$seen_plugin" = yes ] && [ "$seen_cloud_port" = yes ] || return 1
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
