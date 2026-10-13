#!/bin/sh
# Boots PINNED official OpenWrt guest images; no physical routers touched.
set -eu
ARCH="${1:-}"
MODE="${2:-boot}"
case "$MODE" in
    boot|stage) ;;
    *) echo "usage: boot-smoke.sh x86_64|mipsel [boot|stage]" >&2; exit 2 ;;
esac
OPENWRT_VERSION=25.12.5
ROOT=$(CDPATH= cd "$(dirname "$0")/../../.." && pwd) || exit 1
WORK_DIR="${RUNNER_TEMP:-/tmp}/uu-cross-arch-${ARCH}"
case "$ARCH" in
    x86_64)
        REL_TARGET=x86/64
        IMAGE="openwrt-${OPENWRT_VERSION}-x86-64-generic-ext4-combined.img.gz"
        HASH=23e2538e8ab0eb52dfed1c65d608ecdb71ffd432dd54885da138ae67cd9e4461
        ;;
    mipsel)
        REL_TARGET=malta/le
        IMAGE="openwrt-${OPENWRT_VERSION}-malta-le-vmlinux-initramfs.elf"
        HASH=a2aec5d5bd31d411511fd799f936ea0c3d9a878dbc4b2729c600d3f3953931ca
        ;;
    *) echo 'usage: boot-smoke.sh x86_64|mipsel' >&2; exit 2 ;;
esac
command -v expect >/dev/null 2>&1 || { echo 'expect is required' >&2; exit 2; }
command -v sha256sum >/dev/null 2>&1 || exit 2
mkdir -p "$WORK_DIR"
if [ ! -f "$WORK_DIR/$IMAGE" ]; then
    curl -fsSL --retry 3 --connect-timeout 15 --max-time 120 \
       "https://downloads.openwrt.org/releases/$OPENWRT_VERSION/targets/$REL_TARGET/$IMAGE" \
       -o "$WORK_DIR/$IMAGE"
fi
printf '%s  %s\n' "$HASH" "$WORK_DIR/$IMAGE" | sha256sum -c -
if [ "$ARCH" = x86_64 ]; then
    gzip -dc "$WORK_DIR/$IMAGE" > "$WORK_DIR/openwrt-x86.raw"
    GUEST_IMAGE="$WORK_DIR/openwrt-x86.raw"
else
    GUEST_IMAGE="$WORK_DIR/$IMAGE"
fi
if [ "$MODE" = stage ]; then
    command -v python3 >/dev/null 2>&1 || { echo 'python3 is required for local relay' >&2; exit 2; }
    RELAY_DIR="$WORK_DIR/official-relay"
    sh "$ROOT/labs/qemu/cross-arch/prepare-official-stage.sh" "$ARCH" "$RELAY_DIR"
    # Loopback-only host server. The guest connects via its QEMU user-network
    # gateway, not the internet; we re-check the exact MD5 INSIDE the guest.
    RELAY_PORT=8765
    python3 -m http.server "$RELAY_PORT" --bind localhost --directory "$RELAY_DIR" > "$WORK_DIR/local-relay.log" 2>&1 &
    relay_pid=$!
    trap 'kill "$relay_pid" 2>/dev/null || true' EXIT HUP INT TERM
    sleep 1
    kill -0 "$relay_pid" 2>/dev/null || { echo 'Local relay failed to start' >&2; exit 4; }
    curl -fsS --connect-timeout 3 --max-time 5 "http://localhost:$RELAY_PORT/expected-md5.txt" -o /dev/null
    expect "$ROOT/labs/qemu/cross-arch/official-stage.exp" "$ARCH" "$GUEST_IMAGE" "$RELAY_PORT"
    echo "QEMU_CROSS_ARCH_OFFICIAL_STAGE_PASS $ARCH"
else
    expect "$ROOT/labs/qemu/cross-arch/boot-smoke.exp" "$ARCH" "$GUEST_IMAGE"
    echo "QEMU_CROSS_ARCH_BOOT_PASS $ARCH"
fi
