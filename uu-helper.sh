#!/bin/sh

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd) || exit 1
# shellcheck source=lib/channel.sh
. "$ROOT_DIR/lib/channel.sh"

print_usage() {
    cat <<'EOF'
UU Remote WOL Router Helper (Private Draft)

Usage:
  sh uu-helper.sh diagnose
  sh uu-helper.sh collect-info
  sh uu-helper.sh check-api [channel]
  sh uu-helper.sh preflight
  sh uu-helper.sh stage [channel|auto]
  sh uu-helper.sh help

Commands:
  diagnose      Read-only platform detection and UU health summary.
  collect-info  Read-only environment report for unsupported routers.
  check-api     Read-only NetEase UU plugin API check.
  preflight     Read-only platform-aware readiness checks before staging/smoke-test.
  stage         Download, verify and extract the official package under /tmp only; use 'auto' to select a confirmed OpenWrt channel by architecture.
  help          Show this help.

The stage command writes temporary files under /tmp but does not stop/start UU or modify persistent paths.
This draft does not expose an install command.
EOF
}

find_known_uu_plugin_dir() {
    for dir in \
        /userdisk/appdata/2882303761518031252 \
        /jffs/uu \
        /data/uuplugin \
        /usr/share/uuplugin \
        /etc/uuplugin
    do
        if [ -f "$dir/uuplugin" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
    done
    return 1
}

run_diagnose() {
    printf '%s\n' "UU Remote WOL Router Helper - diagnose"
    printf '%s\n' "====================================="
    printf '%s\n' "mode: read-only"
    printf '\n'

    xq_output=$(sh "$ROOT_DIR/platforms/xiaoqiang/detect.sh" 2>&1)
    xq_rc=$?

    if [ "$xq_rc" -eq 0 ]; then
        printf '%s\n' "platform: xiaoqiang"
        printf '%s\n' "$xq_output"
        printf '\n'

        plugin_dir=$(find_known_uu_plugin_dir 2>/dev/null || true)
        if [ -z "$plugin_dir" ]; then
            printf '%s\n' "uu_plugin_dir: not_detected"
            printf '%s\n' "health: not_available"
            printf '%s\n' "next: run collect-info and review the device profile before installation"
            return 1
        fi

        printf 'uu_plugin_dir: %s\n\n' "$plugin_dir"
        UU_PLUGIN_DIR="$plugin_dir" sh "$ROOT_DIR/platforms/xiaoqiang/health.sh"
        health_rc=$?

        case "$health_rc" in
            0) printf '\nhealth_summary: healthy\n' ;;
            *) printf '\nhealth_summary: attention_required\n' ;;
        esac
        return "$health_rc"
    fi

    asus_output=$(sh "$ROOT_DIR/platforms/asuswrt/detect.sh" 2>&1)
    asus_rc=$?

    if [ "$asus_rc" -eq 0 ]; then
        printf '%s\n' "platform: asuswrt"
        printf '%s\n' "$asus_output"
        printf '\n'

        sh "$ROOT_DIR/platforms/asuswrt/health.sh"
        health_rc=$?

        case "$health_rc" in
            0) printf '\nhealth_summary: healthy\n' ;;
            2) printf '\nhealth_summary: uu_not_installed\n' ;;
            *) printf '\nhealth_summary: attention_required\n' ;;
        esac
        return "$health_rc"
    fi

    owrt_output=$(sh "$ROOT_DIR/platforms/openwrt/detect.sh" 2>&1)
    owrt_rc=$?

    if [ "$owrt_rc" -eq 0 ]; then
        printf '%s\n' "platform: openwrt"
        printf '%s\n' "$owrt_output"
        printf '\n'

        sh "$ROOT_DIR/platforms/openwrt/health.sh"
        health_rc=$?

        case "$health_rc" in
            0) printf '\nhealth_summary: healthy\n' ;;
            2) printf '\nhealth_summary: uu_not_installed\n' ;;
            *) printf '\nhealth_summary: attention_required\n' ;;
        esac
        return "$health_rc"
    fi

    printf '%s\n' "platform: unknown"
    printf '%s\n' "matched_adapter: none"
    printf '%s\n' "action: collect-only; no installation will be attempted"
    printf '\n'
    sh "$ROOT_DIR/scripts/collect-info.sh"
    return 2
}

command_name="${1:-help}"

case "$command_name" in
    diagnose)
        run_diagnose
        ;;
    collect-info)
        exec sh "$ROOT_DIR/scripts/collect-info.sh"
        ;;
    check-api)
        shift
        exec sh "$ROOT_DIR/scripts/check-api.sh" "${1:-openwrt-aarch64}"
        ;;
    preflight)
        if sh "$ROOT_DIR/platforms/xiaoqiang/detect.sh" >/dev/null 2>&1; then
            exec sh "$ROOT_DIR/platforms/xiaoqiang/preflight.sh"
        fi
        if sh "$ROOT_DIR/platforms/asuswrt/detect.sh" >/dev/null 2>&1; then
            echo "ASUSWRT uses an official/model-specific integration path; generic preflight is not selected automatically." >&2
            exit 2
        fi
        if sh "$ROOT_DIR/platforms/openwrt/detect.sh" >/dev/null 2>&1; then
            exec sh "$ROOT_DIR/platforms/openwrt/preflight.sh"
        fi
        echo "No supported platform adapter matched for preflight." >&2
        exit 2
        ;;
    stage)
        shift
        requested_channel="${1:-auto}"
        if [ "$requested_channel" != "auto" ]; then
            exec sh "$ROOT_DIR/scripts/stage-package.sh" "$requested_channel"
        fi

        platform=""
        if sh "$ROOT_DIR/platforms/xiaoqiang/detect.sh" >/dev/null 2>&1; then
            platform="xiaoqiang"
        elif sh "$ROOT_DIR/platforms/asuswrt/detect.sh" >/dev/null 2>&1; then
            platform="asuswrt"
        elif sh "$ROOT_DIR/platforms/openwrt/detect.sh" >/dev/null 2>&1; then
            platform="openwrt"
        else
            echo "Unable to auto-select a UU channel: no supported platform adapter matched." >&2
            exit 2
        fi

        arch=$(uname -m 2>/dev/null || printf 'unknown')
        if ! channel=$(uu_resolve_channel "$platform" "$arch"); then
            rc=$?
            if [ "$rc" -eq 2 ]; then
                echo "ASUSWRT auto staging is intentionally disabled; use the official/model-specific integration path." >&2
            else
                printf 'No confirmed UU channel mapping for platform=%s architecture=%s.\n' "$platform" "$arch" >&2
            fi
            exit 3
        fi

        printf 'auto_channel: %s\n' "$channel"
        exec sh "$ROOT_DIR/scripts/stage-package.sh" "$channel"
        ;;
    help|-h|--help)
        print_usage
        ;;
    *)
        printf 'Unknown command: %s\n\n' "$command_name" >&2
        print_usage >&2
        exit 64
        ;;
esac
