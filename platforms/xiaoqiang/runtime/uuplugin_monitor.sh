#!/bin/sh

# RB06-verified runtime monitor template.
# Derived from the final hardware-tested 2026-08-30 configuration.

PLUGIN_DIR="${UU_PLUGIN_DIR:-/userdisk/appdata/2882303761518031252}"
LOG="${UU_MONITOR_LOG:-/tmp/uu-v14-monitor.log}"

export PATH="$PLUGIN_DIR:$PATH"

while :
do
    if ! ps | grep '[u]uplugin ./uu.conf' >/dev/null 2>&1; then
        cd "$PLUGIN_DIR" || exit 1
        ./uuplugin ./uu.conf >>"$LOG" 2>&1 &
    fi
    sleep 60
done
