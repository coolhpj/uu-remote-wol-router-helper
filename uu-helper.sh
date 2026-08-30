#!/bin/sh

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd) || exit 1

print_usage() {
    cat <<'EOF'
UU Remote WOL Router Helper (Private Draft)

Usage:
  sh uu-helper.sh diagnose
  sh uu-helper.sh collect-info
  sh uu-helper.sh check-api [channel]
  sh uu-helper.sh help

Commands:
  diagnose      Read-only platform detection and UU health summary.
  collect-info  Read-only environment report for unsupported routers.
  check-api     Read-only NetEase UU plugin API check.
  help          Show this help.

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
    help|-h|--help)
        print_usage
        ;;
    *)
        printf 'Unknown command: %s\n\n' "$command_name" >&2
        print_usage >&2
        exit 64
        ;;
esac
