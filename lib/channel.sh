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
        *)
            return 1
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
