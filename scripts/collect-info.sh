#!/bin/sh
# UU Remote WOL Router Helper - read-only environment collector
# This script does not modify router configuration and intentionally avoids
# collecting WAN IPs, MAC addresses, serial numbers, PPPoE credentials,
# account credentials, tokens, or device verification codes.

set -u

say() {
    printf '%s\n' "$*"
}

have() {
    command -v "$1" >/dev/null 2>&1
}

read_first_line() {
    file="$1"
    if [ -r "$file" ]; then
        IFS= read -r line < "$file" 2>/dev/null || true
        printf '%s' "$line"
    fi
}

safe_release_value() {
    key="$1"
    file="$2"
    if [ -r "$file" ]; then
        value=$(grep "^${key}=" "$file" 2>/dev/null | head -n 1 | cut -d= -f2-)
        value=$(printf '%s' "$value" | sed 's/^"//; s/"$//')
        printf '%s' "$value"
    fi
}

bool_cmd() {
    if have "$1"; then
        printf 'yes'
    else
        printf 'no'
    fi
}

path_state() {
    path="$1"
    if [ -d "$path" ]; then
        if [ -w "$path" ]; then
            printf 'present,writable'
        else
            printf 'present,read-only'
        fi
    else
        printf 'absent'
    fi
}

model=""
if [ -r /tmp/sysinfo/model ]; then
    model=$(read_first_line /tmp/sysinfo/model)
elif [ -r /proc/device-tree/model ]; then
    model=$(tr -d '\000' < /proc/device-tree/model 2>/dev/null || true)
fi

os_name=$(safe_release_value NAME /etc/os-release)
os_version=$(safe_release_value VERSION_ID /etc/os-release)
openwrt_release=""
if [ -r /etc/openwrt_release ]; then
    openwrt_release=$(grep '^DISTRIB_RELEASE=' /etc/openwrt_release 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d "'\"")
fi

arch=$(uname -m 2>/dev/null || printf 'unknown')
kernel=$(uname -r 2>/dev/null || printf 'unknown')
hostname_safe=""
if have uci; then
    hostname_safe=$(uci -q get system.@system[0].hostname 2>/dev/null || true)
fi

uu_proc_count=0
if have ps; then
    uu_proc_count=$(ps 2>/dev/null | grep -E '[u]uplugin|[x]uplugin-guardian|[u]uplugin_monitor' | wc -l | tr -d ' ')
fi

uu_cloud_established=0
if have netstat; then
    uu_cloud_established=$(netstat -anp 2>/dev/null | grep ':16000' | grep ESTABLISHED | grep -c 'uuplugin' 2>/dev/null || true)
elif have ss; then
    uu_cloud_established=$(ss -ntp 2>/dev/null | grep ':16000' | grep ESTAB | grep -c 'uuplugin' 2>/dev/null || true)
fi

uu_known_path="none"
for p in \
    /userdisk/appdata/2882303761518031252 \
    /jffs/uu \
    /data/uu-v14 \
    /data/uuplugin \
    /usr/share/uuplugin \
    /etc/uuplugin
 do
    if [ -e "$p" ]; then
        if [ "$uu_known_path" = "none" ]; then
            uu_known_path="$p"
        else
            uu_known_path="$uu_known_path,$p"
        fi
    fi
 done

say 'UU Remote WOL Router Helper - collect-info'
say '=========================================='
say 'mode: read-only'
say 'privacy: WAN IP / MAC / SN / PPPoE / accounts / tokens are intentionally not collected'
say ''
say '[system]'
say "model: ${model:-unknown}"
say "architecture: ${arch:-unknown}"
say "kernel: ${kernel:-unknown}"
say "os_name: ${os_name:-unknown}"
say "os_version: ${os_version:-unknown}"
say "openwrt_release: ${openwrt_release:-unknown}"
say "hostname: ${hostname_safe:-unknown}"
say ''
say '[platform-capabilities]'
say "uci: $(bool_cmd uci)"
say "ubus: $(bool_cmd ubus)"
say "opkg: $(bool_cmd opkg)"
say "nvram: $(bool_cmd nvram)"
say "procd: $(bool_cmd procd)"
say "iptables: $(bool_cmd iptables)"
say "nft: $(bool_cmd nft)"
say "netstat: $(bool_cmd netstat)"
say "ss: $(bool_cmd ss)"
say ''
say '[persistent-storage-candidates]'
for p in /data /jffs /overlay /userdisk/appdata /opt; do
    say "$p: $(path_state "$p")"
done
say ''
say '[uu-status]'
say "known_paths: $uu_known_path"
say "related_process_count: $uu_proc_count"
say "cloud_16000_established_count: $uu_cloud_established"
say ''
say '[notes]'
say '- related_process_count is only a coarse signal; it does not prove UU Remote WOL works.'
say '- cloud_16000_established_count does not prove account binding or auxiliary-device discovery.'
say '- Remote WOL is Verified only after a real mobile-data wake test succeeds.'
