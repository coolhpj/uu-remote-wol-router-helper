#!/bin/sh

# Resolve only channels that have been confirmed against the official NetEase API.
# Unknown architectures must fail closed instead of guessing a channel name.

uu_openwrt_channel_for_arch() {
    arch="$1"
    case "$arch" in
        aarch64|arm64)
            printf '%s\n' "openwrt-aarch64"
            ;;
        x86_64|amd64)
            printf '%s\n' "openwrt-x86_64"
            ;;
        mipsel_24kc)
            # Explicit OpenWrt package architecture only; generic 'mips'
            # does not identify endianness or a compatible ABI.
            printf '%s\n' "openwrt-mipsel"
            ;;
        *)
            return 1
            ;;
    esac
}

# Determine the package architecture for the actual OpenWrt host.
# On MIPS, uname -m often only says 'mips'; require a matching OpenWrt
# release architecture and opkg package architecture before choosing a
# NetEase channel. Never infer endianness from 'mips' alone.
uu_openwrt_detect_arch() {
    if [ -n "${UU_ARCH_OVERRIDE:-}" ]; then
        # Overrides are for isolated fixture tests only, never real installs.
        # Even a test override cannot stand in for independent MIPS evidence.
        [ "${UU_TEST_MODE:-0}" = "1" ] || return 1
        case "$UU_ARCH_OVERRIDE" in mips*) return 1 ;; esac
        printf '%s\n' "$UU_ARCH_OVERRIDE"
        return 0
    fi

    kernel_arch=$(uname -m 2>/dev/null || printf 'unknown')
    case "$kernel_arch" in
        mips|mipsel)
            release_file="${UU_OPENWRT_RELEASE_FILE:-/etc/openwrt_release}"
            [ -r "$release_file" ] || return 1
            reported_arch=$(sed -n "s/^DISTRIB_ARCH=['\"]\{0,1\}\([^'\" ]*\)['\"]\{0,1\}$/\1/p" "$release_file" | head -n 1)
            [ "$reported_arch" = "mipsel_24kc" ] || return 1
            command -v opkg >/dev/null 2>&1 || return 1
            opkg print-architecture 2>/dev/null | grep -Eq '^arch mipsel_24kc [0-9]+$' || return 1
            printf '%s\n' "$reported_arch"
            ;;
        mipseb)
            # Big-endian support remains unvalidated for this project.
            return 1
            ;;
        *)
            printf '%s\n' "$kernel_arch"
            ;;
    esac
}

uu_resolve_channel() {
    platform="$1"
    arch="$2"

    case "$platform" in
        xiaoqiang|openwrt)
            uu_openwrt_channel_for_arch "$arch"
            ;;
        asuswrt)
            # ASUSWRT is an official integration path. Generic auto staging is
            # intentionally not selected here because model-specific server
            # routing and installer behavior may differ.
            return 2
            ;;
        *)
            return 1
            ;;
    esac
}
