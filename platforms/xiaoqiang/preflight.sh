#!/bin/sh

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/../.." 2>/dev/null && pwd) || exit 1

MIN_TMP_KB="${UU_MIN_TMP_KB:-16384}"

fail() {
    printf 'preflight: fail\nreason: %s\n' "$1" >&2
    exit "${2:-1}"
}

printf '%s\n' "XiaoQiang UU preflight"
printf '%s\n' "====================="
printf '%s\n' "mode: read-only"

detect_output=$(sh "$ROOT_DIR/platforms/xiaoqiang/detect.sh" 2>&1)
detect_rc=$?
if [ "$detect_rc" -ne 0 ]; then
    fail "xiaoqiang platform not detected" 2
fi
printf '%s\n' "$detect_output"

arch=$(uname -m 2>/dev/null || printf 'unknown')
case "$arch" in
    aarch64|arm64)
        printf 'architecture_check: pass (%s)\n' "$arch"
        ;;
    *)
        fail "unsupported architecture: $arch" 3
        ;;
esac

netmode=""
if command -v uci >/dev/null 2>&1; then
    netmode=$(uci -q get xiaoqiang.common.NETMODE 2>/dev/null || true)
fi

case "$netmode" in
    wifiapmode|lanapmode)
        fail "AP mode is not supported for this adapter: $netmode" 4
        ;;
    '')
        fail "xiaoqiang NETMODE could not be determined" 4
        ;;
    *)
        printf 'netmode_check: pass (%s)\n' "$netmode"
        ;;
esac

for cmd in tar grep sed wc awk df; do
    command -v "$cmd" >/dev/null 2>&1 || fail "required command missing: $cmd" 5
    printf 'tool_%s: present\n' "$cmd"
done

if command -v curl >/dev/null 2>&1; then
    printf '%s\n' "tool_downloader: curl"
elif command -v wget >/dev/null 2>&1; then
    printf '%s\n' "tool_downloader: wget"
else
    fail "neither curl nor wget is available" 5
fi

if command -v md5sum >/dev/null 2>&1; then
    printf '%s\n' "tool_md5: md5sum"
elif command -v busybox >/dev/null 2>&1 && busybox md5sum </dev/null >/dev/null 2>&1; then
    printf '%s\n' "tool_md5: busybox md5sum"
else
    fail "no MD5 implementation is available" 5
fi

[ -d /tmp ] || fail "/tmp does not exist" 6
[ -w /tmp ] || fail "/tmp is not writable" 6
printf '%s\n' "tmp_writable: yes"

available_kb=$(df -Pk /tmp 2>/dev/null | awk 'NR==2 {print $4}')
case "$available_kb" in
    ''|*[!0-9]*)
        fail "unable to determine /tmp free space" 6
        ;;
    *)
        printf 'tmp_available_kb: %s\n' "$available_kb"
        ;;
esac

if [ "$available_kb" -lt "$MIN_TMP_KB" ]; then
    fail "/tmp free space below required threshold: ${available_kb}KB < ${MIN_TMP_KB}KB" 6
fi
printf 'tmp_space_check: pass (minimum=%sKB)\n' "$MIN_TMP_KB"

printf '%s\n' "PREFLIGHT_OK"
printf '%s\n' "No persistent configuration or UU process was modified."
