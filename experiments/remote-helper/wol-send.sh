#!/bin/sh
# Experimental explicit WoL sender. DEFAULT: preview, NO network operations.
# The optional one-shot send uses socat SO_BINDTODEVICE and local-source bind.
# NO UU auth or cloud control. This is not an installed service.
set -eu
usage() {
    echo "usage: sh wol-send.sh [--send] <target-IPv4> <target-MAC> [LAN-interface]" >&2
    exit 64
}

send=no
if [ "${1:-}" = "--send" ]; then send=yes; shift; fi
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || usage
target=$1
mac=$2
iface=${3:-}
base=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if ! details=$(sh "$base/lan-discover.sh" "$target" "$iface" 2>&1); then
    echo "REJECT_WOL: LAN discovery failed" >&2
    printf '%s\n' "$details" >&2
    exit 65
fi
if ! packet_hex=$(sh "$base/magic-packet-hex.sh" "$mac" 2>&1); then
    echo "REJECT_WOL: target MAC is invalid" >&2
    printf '%s\n' "$packet_hex" >&2
    exit 65
fi

local_ip=$(printf '%s\n' "$details" | awk '/^local_ipv4: / {print $2}')
selected=$(printf '%s\n' "$details" | awk '/^lan_interface: / {print $2}')
broadcast=$(printf '%s\n' "$details" | awk '/^directed_broadcast: / {print $2}')
[ -n "$local_ip" ] && [ -n "$selected" ] && [ -n "$broadcast" ] || {
    echo "REJECT_WOL: missing validated LAN details" >&2
    exit 65
}
if [ "$send" = no ]; then
    printf '%s\n' "REMOTE_WOL_SEND_PREVIEW_PASS" "lan_interface: $selected" \
        "directed_broadcast: $broadcast" "target_mac_format: valid_unicast" \
        "magic_packet_bytes: 102" "wol_packet_sent: no" \
        "uu_registration_attempted: no"
    exit 0
fi

# Two separate confirmations: explicit --send flag and a one-shot local intent.
# Future authenticated cloud-push handling must have its own authorization contract.
if [ "${UU_WOL_SEND_CONFIRM:-}" != "SEND_ONE_WOL_PACKET" ]; then
    echo "REJECT_WOL_SEND: explicit one-shot confirmation is required" >&2
    exit 66
fi
if ! command -v socat >/dev/null 2>&1; then
    echo "REJECT_WOL_SEND: socat is unavailable (no alternate network transport)" >&2
    exit 69
fi
if ! command -v ip >/dev/null 2>&1; then
    echo "REJECT_WOL_SEND: cannot verify selected LAN route" >&2
    exit 69
fi
if ! route=$(ip -4 route get "$broadcast" 2>/dev/null); then
    echo "REJECT_WOL_SEND: route-get unsupported or route missing" >&2
    exit 69
fi
if ! printf '%s\n' "$route" | awk -v want_dev="$selected" -v want_src="$local_ip" '
    {
        dev=0; src=0
        for(i=1;i<NF;i++) {
            if($i=="dev" && $(i+1)==want_dev) dev=1
            if($i=="src" && $(i+1)==want_src) src=1
            if($i=="via" || $i=="gateway") routed=1
        }
        if(dev && src) ok=1
    }
    END { exit(ok && !routed ? 0 : 1) }
'; then
    echo "REJECT_WOL_SEND: route does not use selected interface and source IP" >&2
    exit 66
fi

# The encoder emits ASCII HEX only. Convert to portable POSIX printf %b octal
# escapes without binary temp files and without depending on Perl/Python/Rust.
octal=$(awk -v hex="$packet_hex" '
    BEGIN {
        if(length(hex)!=204 || hex !~ /^[0-9A-F]+$/) exit 65
        alphabet="0123456789ABCDEF"
        for(i=1;i<=204;i+=2) {
            h=index(alphabet,substr(hex,i,1))-1
            l=index(alphabet,substr(hex,i+1,1))-1
            if(h<0 || l<0) exit 65
            printf "\\0%03o", (16*h+l)
        }
    }
')
[ -n "$octal" ] || { echo "REJECT_WOL_SEND: no encoded payload" >&2; exit 65; }

# Failure to bind to the requested NIC is fatal. Never fall back to an
# unrestricted broadcast or a different interface. One datagram, port 9.
if ! printf '%b' "$octal" | socat -u - "UDP4-DATAGRAM:$broadcast:9,broadcast,so-bindtodevice=$selected,bind=$local_ip,dontroute,shut-none"; then
    echo "WOL_SEND_FAILED: socket writer failed; no success claim" >&2
    exit 69
fi
printf '%s\n' "REMOTE_WOL_SOCKET_WRITE_PASS" "lan_interface: $selected" \
    "directed_broadcast: $broadcast" "bytes_submitted: 102" \
    "note: destination PC wake not verified"
