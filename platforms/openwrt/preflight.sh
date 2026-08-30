#!/bin/sh

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/../.." 2>/dev/null && pwd) || exit 1
# shellcheck source=../../lib/channel.sh
. "$ROOT_DIR/lib/channel.sh"

RELEASE_FILE="${UU_OPENWRT_RELEASE_FILE:-/etc/openwrt_release}"
ARCH="${UU_ARCH_OVERRIDE:-$(uname -m 2>/dev/null || printf 'unknown')}"

printf '%s\n' "Generic OpenWrt UU preflight"
printf '%s\n' "============================"
printf '%s\n' "mode: read-only"

if [ ! -f "$RELEASE_FILE" ]; then
    echo "preflight: fail"
    echo "reason: OpenWrt release metadata not detected"
    exit 2
fi

arch="$ARCH"
if ! channel=$(uu_openwrt_channel_for_arch "$arch"); then
    echo "preflight: fail"
    printf 'architecture: %s\n' "$arch"
    echo "reason: no confirmed official OpenWrt channel for this architecture"
    exit 3
fi

missing=""
for cmd in tar md5sum sed grep ps df awk; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        missing="$missing $cmd"
    fi
done

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    missing="$missing curl-or-wget"
fi

if [ -n "$missing" ]; then
    echo "preflight: fail"
    printf 'architecture: %s\n' "$arch"
    printf 'channel: %s\n' "$channel"
    printf 'missing_tools:%s\n' "$missing"
    exit 4
fi

if [ ! -d /tmp ] || [ ! -w /tmp ]; then
    echo "preflight: fail"
    echo "reason: /tmp is not writable"
    exit 5
fi

avail_kb=$(df -Pk /tmp 2>/dev/null | awk 'NR==2 {print $4}')
case "$avail_kb" in
    ''|*[!0-9]*) avail_kb=0 ;;
esac

# Staging currently needs roughly 10 MB; keep a conservative floor.
if [ "$avail_kb" -lt 20480 ]; then
    echo "preflight: fail"
    printf 'tmp_available_kb: %s\n' "$avail_kb"
    echo "reason: less than 20 MiB free in /tmp"
    exit 6
fi

root_status="no"
if [ "$(id -u 2>/dev/null || printf 1)" = "0" ]; then
    root_status="yes"
fi

. "$RELEASE_FILE" 2>/dev/null || true
printf 'preflight: pass\n'
printf 'architecture: %s\n' "$arch"
printf 'channel: %s\n' "$channel"
printf 'release: %s\n' "${DISTRIB_DESCRIPTION:-unknown}"
printf 'target: %s\n' "${DISTRIB_TARGET:-unknown}"
printf 'root: %s\n' "$root_status"
printf 'tmp_available_kb: %s\n' "$avail_kb"
printf '%s\n' "persistent_changes: no"
