#!/bin/sh

# Read-only generic OpenWrt UU health check.

PLUGIN_DIR="${UU_OPENWRT_PLUGIN_DIR:-}"

have_cmd() {
    name="$1"
    command -v "$name" >/dev/null 2>&1 && return 0
    for dir in /bin /sbin /usr/bin /usr/sbin; do
        [ -x "$dir/$name" ] && return 0
    done
    return 1
}

if [ -z "$PLUGIN_DIR" ]; then
    for dir in \
        /usr/share/uuplugin \
        /etc/uuplugin \
        /data/uuplugin \
        /tmp/uu \
        /userdisk/appdata/2882303761518031252
    do
        if [ -f "$dir/uuplugin" ] || [ -f "$dir/uu.conf" ]; then
            PLUGIN_DIR="$dir"
            break
        fi
    done
fi

[ -n "$PLUGIN_DIR" ] || PLUGIN_DIR="not-detected"

version="unknown"
if [ "$PLUGIN_DIR" != "not-detected" ] && [ -f "$PLUGIN_DIR/uu.conf" ]; then
    value=$(sed -n 's/^version=//p' "$PLUGIN_DIR/uu.conf" | head -n 1)
    [ -n "$value" ] && version="$value"
fi

has_process() {
    pattern="$1"
    ps 2>/dev/null | grep "$pattern" | grep -v grep >/dev/null 2>&1
}

monitor="offline"
plugin="offline"
guardian="offline"
cloud="offline"
firewall_backend="unknown"

has_process '[u]uplugin_monitor' && monitor="online"
has_process '[u]uplugin' && plugin="online"
has_process '[x]uplugin-guardian' && guardian="online"

if have_cmd netstat; then
    if netstat -anp 2>/dev/null | grep ':16000' | grep ESTABLISHED | grep uuplugin >/dev/null 2>&1; then
        cloud="online"
    fi
elif have_cmd ss; then
    if ss -ntp 2>/dev/null | grep ':16000' | grep ESTAB | grep uuplugin >/dev/null 2>&1; then
        cloud="online"
    fi
fi

if have_cmd nft; then
    firewall_backend="nftables"
elif have_cmd iptables; then
    firewall_backend="iptables"
fi

printf '%s\n' "OpenWrt UU health"
printf '%s\n' "================="
printf 'plugin_dir: %s\n' "$PLUGIN_DIR"
printf 'plugin_dir_exists: %s\n' "$([ "$PLUGIN_DIR" != "not-detected" ] && [ -d "$PLUGIN_DIR" ] && printf yes || printf no)"
printf 'version: %s\n' "$version"
printf 'monitor: %s\n' "$monitor"
printf 'uuplugin: %s\n' "$plugin"
printf 'guardian: %s\n' "$guardian"
printf 'cloud_16000: %s\n' "$cloud"
printf 'firewall_backend: %s\n' "$firewall_backend"

if [ "$PLUGIN_DIR" = "not-detected" ] || [ ! -d "$PLUGIN_DIR" ]; then
    exit 2
fi

# Generic OpenWrt may use procd/init instead of a monitor wrapper, so monitor is
# informational only. Runtime + guardian + cloud are the common health gates.
if [ "$plugin" = "online" ] && [ "$guardian" = "online" ] && [ "$cloud" = "online" ]; then
    exit 0
fi

exit 1
