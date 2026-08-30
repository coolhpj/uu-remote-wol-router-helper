#!/bin/sh

# Read-only XiaoQiang UU health check.
# Defaults reflect the verified RB06 sample but can be overridden:
#   UU_PLUGIN_DIR=/path/to/plugin sh health.sh

PLUGIN_DIR="${UU_PLUGIN_DIR:-/userdisk/appdata/2882303761518031252}"
CONF="$PLUGIN_DIR/uu.conf"

version="unknown"
if [ -f "$CONF" ]; then
    version=$(sed -n 's/^version=//p' "$CONF" | head -n 1)
    [ -n "$version" ] || version="unknown"
fi

has_process() {
    pattern="$1"
    ps 2>/dev/null | grep "$pattern" | grep -v grep >/dev/null 2>&1
}

monitor="offline"
plugin="offline"
guardian="offline"
cloud="offline"

has_process '[u]uplugin_monitor' && monitor="online"
has_process '[u]uplugin ./uu.conf' && plugin="online"
has_process '[x]uplugin-guardian' && guardian="online"

if command -v netstat >/dev/null 2>&1; then
    if netstat -anp 2>/dev/null | grep ':16000' | grep ESTABLISHED | grep uuplugin >/dev/null 2>&1; then
        cloud="online"
    fi
elif command -v ss >/dev/null 2>&1; then
    if ss -ntp 2>/dev/null | grep ':16000' | grep ESTAB | grep uuplugin >/dev/null 2>&1; then
        cloud="online"
    fi
fi

netmode="unknown"
if command -v uci >/dev/null 2>&1; then
    value=$(uci -q get xiaoqiang.common.NETMODE 2>/dev/null || true)
    [ -n "$value" ] && netmode="$value"
fi

printf '%s
' "XiaoQiang UU health"
printf '%s
' "=================="
printf 'plugin_dir: %s
' "$PLUGIN_DIR"
printf 'plugin_dir_exists: %s
' "$([ -d "$PLUGIN_DIR" ] && printf yes || printf no)"
printf 'version: %s
' "$version"
printf 'netmode: %s
' "$netmode"
printf 'monitor: %s
' "$monitor"
printf 'uuplugin: %s
' "$plugin"
printf 'guardian: %s
' "$guardian"
printf 'cloud_16000: %s
' "$cloud"

if [ ! -d "$PLUGIN_DIR" ]; then
    exit 2
fi

if [ "$plugin" = "online" ] && [ "$guardian" = "online" ] && [ "$cloud" = "online" ]; then
    exit 0
fi

exit 1
