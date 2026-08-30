#!/bin/sh

# Read-only generic OpenWrt detector.
# XiaoQiang and ASUSWRT adapters are checked before this generic adapter.

RELEASE_FILE="${UU_OPENWRT_RELEASE_FILE:-/etc/openwrt_release}"
SYSINFO_DIR="${UU_OPENWRT_SYSINFO_DIR:-/tmp/sysinfo}"
arch=$(uname -m 2>/dev/null || printf 'unknown')

have_cmd() {
    name="$1"
    command -v "$name" >/dev/null 2>&1 && return 0
    for dir in /bin /sbin /usr/bin /usr/sbin; do
        [ -x "$dir/$name" ] && return 0
    done
    return 1
}

release_value() {
    key="$1"
    [ -f "$RELEASE_FILE" ] || return 1
    sed -n "s/^${key}=['\"]\{0,1\}\([^'\"]*\)['\"]\{0,1\}$/\1/p" "$RELEASE_FILE" | head -n 1
}

matched="no"
[ -f "$RELEASE_FILE" ] && matched="yes"

distrib_id=$(release_value DISTRIB_ID 2>/dev/null || true)
distrib_release=$(release_value DISTRIB_RELEASE 2>/dev/null || true)
distrib_target=$(release_value DISTRIB_TARGET 2>/dev/null || true)
distrib_description=$(release_value DISTRIB_DESCRIPTION 2>/dev/null || true)

model="unknown"
if [ -f "$SYSINFO_DIR/model" ]; then
    value=$(head -n 1 "$SYSINFO_DIR/model" 2>/dev/null || true)
    [ -n "$value" ] && model="$value"
elif [ -f "$SYSINFO_DIR/board_name" ]; then
    value=$(head -n 1 "$SYSINFO_DIR/board_name" 2>/dev/null || true)
    [ -n "$value" ] && model="$value"
fi

uci_state="no"
ubus_state="no"
opkg_state="no"
have_cmd uci && uci_state="yes"
have_cmd ubus && ubus_state="yes"
have_cmd opkg && opkg_state="yes"

overlay="absent"
if [ -d /overlay ]; then
    if [ -w /overlay ]; then
        overlay="present,writable"
    else
        overlay="present,read-only"
    fi
fi

printf '%s\n' "OpenWrt platform detection"
printf '%s\n' "=========================="
printf 'matched: %s\n' "$matched"
printf 'model: %s\n' "$model"
printf 'architecture: %s\n' "$arch"
printf 'distrib_id: %s\n' "${distrib_id:-unknown}"
printf 'release: %s\n' "${distrib_release:-unknown}"
printf 'target: %s\n' "${distrib_target:-unknown}"
printf 'description: %s\n' "${distrib_description:-unknown}"
printf 'uci: %s\n' "$uci_state"
printf 'ubus: %s\n' "$ubus_state"
printf 'opkg: %s\n' "$opkg_state"
printf '/overlay: %s\n' "$overlay"

[ "$matched" = "yes" ]
