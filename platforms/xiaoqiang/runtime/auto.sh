#!/bin/sh

# RB06-verified boot helper template.
# Final validated behavior:
#   1) skip if UU cloud control is already online;
#   2) wait for default route + NetEase API reachability;
#   3) start UU;
#   4) if :16000 is still offline, restart once;
#   5) record final cloud state.

PLUGIN_DIR="${UU_PLUGIN_DIR:-/userdisk/appdata/2882303761518031252}"
LOG="${UU_BOOT_LOG:-/tmp/uu-v14-boot.log}"
API_URL="${UU_API_URL:-https://router.uu.163.com/api/plugin?type=openwrt-aarch64}"

cloud_online() {
    netstat -anp 2>/dev/null | grep ':16000' | grep ESTABLISHED | grep uuplugin >/dev/null 2>&1
}

(
    echo "[$(date)] UU boot helper start" >>"$LOG"

    # firewall reload may call this script again; do not bounce a healthy UU.
    if cloud_online; then
        echo "[$(date)] UU already online, skip" >>"$LOG"
        exit 0
    fi

    # Wait up to about three minutes for routing and the official API.
    count=0
    while [ "$count" -lt 36 ]; do
        if ip route 2>/dev/null | grep '^default ' >/dev/null 2>&1; then
            if curl -fsS --connect-timeout 4 "$API_URL" >/dev/null 2>&1; then
                echo "[$(date)] network ready" >>"$LOG"
                break
            fi
        fi

        count=$((count + 1))
        sleep 5
    done

    echo "[$(date)] starting UU" >>"$LOG"
    "$PLUGIN_DIR/xnetease-uu" plugon

    sleep 15

    # A too-early first registration can leave the process alive but cloud-offline.
    if ! cloud_online; then
        echo "[$(date)] first cloud connect failed, retry" >>"$LOG"
        "$PLUGIN_DIR/xnetease-uu" plugoff
        sleep 3
        "$PLUGIN_DIR/xnetease-uu" plugon
        sleep 15
    fi

    if cloud_online; then
        echo "[$(date)] UU cloud online" >>"$LOG"
    else
        echo "[$(date)] UU cloud still offline" >>"$LOG"
    fi
) &

exit 0
