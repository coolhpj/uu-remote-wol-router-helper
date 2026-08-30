#!/bin/sh

# Read-only XiaoQiang platform detector.
# Exit 0: XiaoQiang indicators found.
# Exit 1: indicators not found.

arch=$(uname -m 2>/dev/null || printf 'unknown')
netmode=""
uci_state="no"

if command -v uci >/dev/null 2>&1; then
    uci_state="yes"
    netmode=$(uci -q get xiaoqiang.common.NETMODE 2>/dev/null || true)
fi

xiaoqiang_config="no"
if [ -e /etc/config/xiaoqiang ]; then
    xiaoqiang_config="yes"
fi

persistent_data="absent"
if [ -d /data ]; then
    if [ -w /data ]; then
        persistent_data="present,writable"
    else
        persistent_data="present,read-only"
    fi
fi

userdisk_appdata="absent"
if [ -d /userdisk/appdata ]; then
    if [ -w /userdisk/appdata ]; then
        userdisk_appdata="present,writable"
    else
        userdisk_appdata="present,read-only"
    fi
fi

matched="no"
if [ -n "$netmode" ] || [ "$xiaoqiang_config" = "yes" ]; then
    matched="yes"
fi

printf '%s
' "XiaoQiang platform detection"
printf '%s
' "============================"
printf 'matched: %s
' "$matched"
printf 'architecture: %s
' "$arch"
printf 'uci: %s
' "$uci_state"
printf 'xiaoqiang_netmode: %s
' "${netmode:-unknown}"
printf 'xiaoqiang_config: %s
' "$xiaoqiang_config"
printf '/data: %s
' "$persistent_data"
printf '/userdisk/appdata: %s
' "$userdisk_appdata"

[ "$matched" = "yes" ]
