#!/bin/sh

# Read-only ASUSWRT UU health check.
# Defaults match the verified RT-AX86U reference sample.

PERSIST_DIR="${UU_ASUS_PERSIST_DIR:-/jffs/uu}"
RUNTIME_DIR="${UU_ASUS_RUNTIME_DIR:-/tmp/uu}"

version="unknown"
for conf in "$RUNTIME_DIR/uu.conf" "$PERSIST_DIR/uu.conf"; do
    if [ -f "$conf" ]; then
        value=$(sed -n 's/^version=//p' "$conf" | head -n 1)
        if [ -n "$value" ]; then
            version="$value"
            break
        fi
    fi
done

have_cmd() {
    name="$1"
    command -v "$name" >/dev/null 2>&1 && return 0
    for dir in /bin /sbin /usr/bin /usr/sbin; do
        [ -x "$dir/$name" ] && return 0
    done
    return 1
}

has_process() {
    pattern="$1"
    ps 2>/dev/null | grep "$pattern" | grep -v grep >/dev/null 2>&1
}

monitor="offline"
plugin="offline"
guardian="offline"
cloud="offline"
mc2="not-detected"

has_process '[u]uplugin_monitor' && monitor="online"
has_process '[u]uplugin' && plugin="online"
has_process '[x]uplugin-guardian' && guardian="online"
has_process '/koolshare/bin/[c]lash' && mc2="online"

if have_cmd netstat; then
    if netstat -anp 2>/dev/null | grep ':16000' | grep ESTABLISHED | grep uuplugin >/dev/null 2>&1; then
        cloud="online"
    fi
elif have_cmd ss; then
    if ss -ntp 2>/dev/null | grep ':16000' | grep ESTAB | grep uuplugin >/dev/null 2>&1; then
        cloud="online"
    fi
fi

model="unknown"
sw_mode="unknown"
if have_cmd nvram; then
    value=$(nvram get productid 2>/dev/null || true)
    [ -n "$value" ] && model="$value"
    value=$(nvram get sw_mode 2>/dev/null || true)
    [ -n "$value" ] && sw_mode="$value"
fi

printf '%s\n' "ASUSWRT UU health"
printf '%s\n' "================="
printf 'model: %s\n' "$model"
printf 'sw_mode: %s\n' "$sw_mode"
printf 'persistent_dir: %s\n' "$PERSIST_DIR"
printf 'persistent_dir_exists: %s\n' "$([ -d "$PERSIST_DIR" ] && printf yes || printf no)"
printf 'runtime_dir: %s\n' "$RUNTIME_DIR"
printf 'runtime_dir_exists: %s\n' "$([ -d "$RUNTIME_DIR" ] && printf yes || printf no)"
printf 'version: %s\n' "$version"
printf 'monitor: %s\n' "$monitor"
printf 'uuplugin: %s\n' "$plugin"
printf 'guardian: %s\n' "$guardian"
printf 'cloud_16000: %s\n' "$cloud"
printf 'mc2_clash_reference: %s\n' "$mc2"

if [ ! -d "$PERSIST_DIR" ] && [ ! -d "$RUNTIME_DIR" ]; then
    exit 2
fi

if [ "$monitor" = "online" ] && [ "$plugin" = "online" ] && [ "$guardian" = "online" ] && [ "$cloud" = "online" ]; then
    exit 0
fi

exit 1
