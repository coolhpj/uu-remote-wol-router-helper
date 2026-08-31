#!/bin/sh
set -eu

OPENWRT_VERSION="${OPENWRT_VERSION:-25.12.5}"
OPENWRT_BASE_URL="${OPENWRT_BASE_URL:-https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/armsr/armv8}"
IMAGE_GZ_NAME="openwrt-${OPENWRT_VERSION}-armsr-armv8-generic-ext4-combined-efi.img.gz"
EXPECTED_SHA256="${OPENWRT_PERSISTENT_IMAGE_SHA256:-d7dcf013547e8be28006d83ce2c2232cd065755b803f4a5ee6b2e22391cfbc76}"
EFI_PATH="${QEMU_EFI_AARCH64:-/usr/share/qemu-efi-aarch64/QEMU_EFI.fd}"
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd) || exit 1
ROOT_DIR=$(CDPATH= cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd) || exit 1
WORK_DIR="${UU_QEMU_PERSIST_WORK_DIR:-${RUNNER_TEMP:-/tmp}/uu-router-lab-arm64-persistent}"
IMAGE_GZ_PATH="$WORK_DIR/$IMAGE_GZ_NAME"
IMAGE_PATH="$WORK_DIR/openwrt-arm64-xiaoqiang-shim.img"

fail() {
    printf 'qemu-arm64-xiaoqiang-shim: fail\nreason: %s\n' "$1" >&2
    exit "${2:-1}"
}

command -v qemu-system-aarch64 >/dev/null 2>&1 || fail "qemu-system-aarch64 is required" 2
command -v expect >/dev/null 2>&1 || fail "expect is required" 2
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required" 2
command -v gzip >/dev/null 2>&1 || fail "gzip is required" 2
[ -f "$EFI_PATH" ] || fail "AArch64 QEMU EFI firmware is missing at $EFI_PATH" 2

mkdir -p "$WORK_DIR"

if [ ! -f "$IMAGE_GZ_PATH" ]; then
    printf 'Downloading official OpenWrt ARM64 persistent image: %s\n' "$IMAGE_GZ_NAME"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --connect-timeout 15 "$OPENWRT_BASE_URL/$IMAGE_GZ_NAME" -o "$IMAGE_GZ_PATH"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$IMAGE_GZ_PATH" "$OPENWRT_BASE_URL/$IMAGE_GZ_NAME"
    else
        fail "curl or wget is required" 2
    fi
fi

printf '%s  %s\n' "$EXPECTED_SHA256" "$IMAGE_GZ_PATH" | sha256sum -c - >/dev/null 2>&1 || \
    fail "OpenWrt persistent image SHA256 mismatch" 3

gzip -dc "$IMAGE_GZ_PATH" > "$IMAGE_PATH" || fail "unable to decompress XiaoQiang shim image" 4

printf '%s\n' "OpenWrt persistent image SHA256: pass"
printf '%s\n' "Starting XiaoQiang compatibility-shim migration/reboot/rollback lifecycle"

expect "$SCRIPT_DIR/xiaoqiang-shim-smoke.exp" "$IMAGE_PATH" "$EFI_PATH" "$ROOT_DIR"

printf '%s\n' "QEMU_ARM64_XIAOQIANG_SHIM_PASS"
