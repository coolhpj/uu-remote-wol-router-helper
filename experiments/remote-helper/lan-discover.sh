#!/bin/sh
# Read-only host LAN discovery. No route modification, no packet, no UU account.
# Never treat the default IPv4 route as proof of LAN role.
set -eu

usage() {
    echo "usage: sh lan-discover.sh <target-IPv4> [explicit-LAN-interface]" >&2
    exit 64
}
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || usage

target=$1
requested=${2:-}
case "$requested" in
    *[!a-zA-Z0-9_.:-]*) echo "REJECT_LAN_INTERFACE: invalid characters" >&2; exit 65 ;;
esac

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -f "$script_dir/lan-candidates.awk" ] || exit 70
[ -f "$script_dir/lan-normalize.awk" ] || exit 70
[ -f "$script_dir/lan-preflight.sh" ] || exit 70

if ! command -v ip >/dev/null 2>&1; then
    echo "LAN_INSPECTION_UNAVAILABLE: ip is required; nothing was changed" >&2
    exit 69
fi
if ! raw=$(ip -o -4 addr show scope global 2>/dev/null); then
    # Some BusyBox ip implementations lack -o or scope filtering. Only read
    # the fallback address list; do not alter routes or infer a default gateway.
    if ! multiline=$(ip -4 addr show 2>/dev/null); then
        echo "LAN_INSPECTION_UNAVAILABLE: neither one-line nor multiline ip output works" >&2
        exit 69
    fi
    if ! raw=$(printf '%s\n' "$multiline" | awk -f "$script_dir/lan-normalize.awk"); then
        echo "LAN_INSPECTION_UNAVAILABLE: cannot parse multiline addresses" >&2
        exit 69
    fi
fi

if ! candidates=$(printf '%s\n' "$raw" | awk -v target="$target" -v requested="$requested" -f "$script_dir/lan-candidates.awk"); then
    echo "REJECT_LAN_DISCOVERY: invalid target or interface output" >&2
    exit 65
fi
if [ -z "$candidates" ]; then
    echo "REJECT_LAN_DISCOVERY: no eligible LAN address matching target; specify a LAN interface if appropriate" >&2
    exit 65
fi
case "$candidates" in
    *'
'*) echo "REJECT_LAN_DISCOVERY: ambiguous multiple LAN addresses; specify LAN interface and resolve IP aliases" >&2; exit 65 ;;
esac

iface=${candidates%%|*}
remaining=${candidates#*|}
local_ip=${remaining%%|*}
netmask=${remaining#*|}
# The earlier parser only selects candidates; the existing validator checks
# subnet boundary, netmask continuity and unsafe roles again.
if ! validated=$(sh "$script_dir/lan-preflight.sh" "$iface" "$local_ip" "$netmask" "$target"); then
    echo "REJECT_LAN_DISCOVERY: selected interface did not pass LAN target preflight" >&2
    exit 65
fi
printf '%s\n' "REMOTE_WOL_LAN_DISCOVERY_PASS" "local_ipv4: $local_ip" "$validated" "route_table_changed: no" "wol_packet_sent: no"
