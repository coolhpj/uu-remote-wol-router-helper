#!/bin/sh
set -eu

OPENWRT_VERSION="${OPENWRT_VERSION:-25.12.5}"
OPENWRT_BASE_URL="${OPENWRT_BASE_URL:-https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/armsr/armv8}"
IMAGE_NAME="openwrt-${OPENWRT_VERSION}-armsr-armv8-generic-initramfs-kernel.bin"
EXPECTED_SHA256="${OPENWRT_IMAGE_SHA256:-f510b0c73c1ee70a64df384d7e2ad4404caf83e6bc7cce9ac13426f77b9ae3be}"
SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd) || exit 1
ROOT_DIR=$(CDPATH= cd "$SCRIPT_DIR/../../.." 2>/dev/null && pwd) || exit 1
WORK_DIR="${UU_QEMU_WORK_DIR:-${RUNNER_TEMP:-/tmp}/uu-router-lab-arm64}"
IMAGE_PATH="$WORK_DIR/$IMAGE_NAME"

fail() {
    printf 'qemu-arm64-stage-lab: fail\nreason: %s\n' "$1" >&2
    exit "${2:-1}"
}

command -v qemu-system-aarch64 >/dev/null 2>&1 || fail "qemu-system-aarch64 is required" 2
command -v expect >/dev/null 2>&1 || fail "expect is required" 2
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required" 2

mkdir -p "$WORK_DIR"

if [ ! -f "$IMAGE_PATH" ]; then
    printf 'Downloading official OpenWrt ARM64 initramfs: %s\n' "$IMAGE_NAME"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --connect-timeout 15 \
            "$OPENWRT_BASE_URL/$IMAGE_NAME" -o "$IMAGE_PATH"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$IMAGE_PATH" "$OPENWRT_BASE_URL/$IMAGE_NAME"
    else
        fail "curl or wget is required" 2
    fi
fi

printf '%s  %s\n' "$EXPECTED_SHA256" "$IMAGE_PATH" | sha256sum -c - >/dev/null 2>&1 || \
    fail "OpenWrt image SHA256 mismatch" 3

printf '%s\n' "OpenWrt image SHA256: pass"
printf '%s\n' "Starting QEMU ARM64 repository staging smoke-test"

expect "$SCRIPT_DIR/stage-smoke.exp" "$IMAGE_PATH" "$ROOT_DIR"

printf '%s\n' "QEMU_ARM64_STAGE_SMOKE_PASS"
