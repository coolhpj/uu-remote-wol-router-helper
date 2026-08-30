#!/bin/sh
set -u

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/lib/channel.sh"

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    expected="$1"
    actual="$2"
    label="$3"
    [ "$expected" = "$actual" ] || fail "$label (expected=$expected actual=$actual)"
    printf 'ok - %s\n' "$label"
}

assert_eq openwrt-aarch64 "$(uu_openwrt_channel_for_arch aarch64)" "map aarch64 OpenWrt channel"
assert_eq openwrt-aarch64 "$(uu_openwrt_channel_for_arch arm64)" "map arm64 alias"
assert_eq openwrt-x86_64 "$(uu_openwrt_channel_for_arch x86_64)" "map x86_64 OpenWrt channel"
assert_eq openwrt-x86_64 "$(uu_openwrt_channel_for_arch amd64)" "map amd64 alias"
assert_eq openwrt-x86_64 "$(uu_resolve_channel openwrt x86_64)" "resolve Generic OpenWrt channel"
assert_eq openwrt-aarch64 "$(uu_resolve_channel xiaoqiang aarch64)" "resolve XiaoQiang channel"

if uu_openwrt_channel_for_arch mipsel >/dev/null 2>&1; then
    fail "unknown architecture must fail closed"
fi
printf 'ok - unknown architecture fails closed\n'

uu_resolve_channel asuswrt aarch64 >/dev/null 2>&1
asus_rc=$?
[ "$asus_rc" -eq 2 ] || fail "ASUSWRT must return model-specific status"
printf 'ok - ASUSWRT auto staging is intentionally disabled\n'

printf 'all channel mapping tests passed\n'
