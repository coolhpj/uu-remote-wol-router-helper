#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "wol-packet-smoke.sh must run as root for network namespaces/raw packets" >&2
    exit 2
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PACKET_TOOL="$SCRIPT_DIR/wol-packet-smoke.py"

ROUTER_NS=uuw-router
TARGET_NS=uuw-target
BRIDGE=uuw-br
ROUTER_BR=uuw-rb
ROUTER_IF=uuw-r0
TARGET_BR=uuw-tb
TARGET_IF=uuw-t0
SOURCE_HEX=02aabbccddee
TARGET_HEX=021122334455
PCAP=/tmp/uu-wol-helper-stage7-target.pcap
TCPDUMP_LOG=/tmp/uu-wol-helper-stage7-tcpdump.log
CAP_PID=

hex_to_mac() {
    printf '%s\n' "$1" | sed -E 's/(..)(..)(..)(..)(..)(..)/\1:\2:\3:\4:\5:\6/'
}

cleanup() {
    if [ -n "$CAP_PID" ]; then
        kill -INT "$CAP_PID" 2>/dev/null || true
        wait "$CAP_PID" 2>/dev/null || true
    fi
    ip netns del "$ROUTER_NS" 2>/dev/null || true
    ip netns del "$TARGET_NS" 2>/dev/null || true
    ip link del "$BRIDGE" 2>/dev/null || true
    rm -f "$PCAP" "$TCPDUMP_LOG"
}
trap cleanup EXIT INT TERM

command -v ip >/dev/null 2>&1 || { echo "ip command is required" >&2; exit 3; }
command -v tcpdump >/dev/null 2>&1 || { echo "tcpdump is required" >&2; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 3; }
[ -f "$PACKET_TOOL" ] || { echo "packet tool missing: $PACKET_TOOL" >&2; exit 3; }

# Build a fully isolated two-node Ethernet LAN. The target-side capture proves
# that both packets crossed the virtual switch instead of merely being created.
ip netns add "$ROUTER_NS"
ip netns add "$TARGET_NS"
ip link add "$BRIDGE" type bridge
ip link set "$BRIDGE" up

ip link add "$ROUTER_BR" type veth peer name "$ROUTER_IF"
ip link set "$ROUTER_BR" master "$BRIDGE"
ip link set "$ROUTER_BR" up
ip link set "$ROUTER_IF" netns "$ROUTER_NS"
ip netns exec "$ROUTER_NS" ip link set lo up
ip netns exec "$ROUTER_NS" ip link set "$ROUTER_IF" address "$(hex_to_mac "$SOURCE_HEX")"
ip netns exec "$ROUTER_NS" ip link set "$ROUTER_IF" up

ip link add "$TARGET_BR" type veth peer name "$TARGET_IF"
ip link set "$TARGET_BR" master "$BRIDGE"
ip link set "$TARGET_BR" up
ip link set "$TARGET_IF" netns "$TARGET_NS"
ip netns exec "$TARGET_NS" ip link set lo up
ip netns exec "$TARGET_NS" ip link set "$TARGET_IF" address "$(hex_to_mac "$TARGET_HEX")"
ip netns exec "$TARGET_NS" ip link set "$TARGET_IF" up

rm -f "$PCAP" "$TCPDUMP_LOG"
ip netns exec "$TARGET_NS" tcpdump -U -n -s 0 -i "$TARGET_IF" \
    -w "$PCAP" 'udp dst port 9 or ether proto 0x0842' >"$TCPDUMP_LOG" 2>&1 &
CAP_PID=$!
sleep 1

ip netns exec "$ROUTER_NS" python3 "$PACKET_TOOL" send \
    --interface "$ROUTER_IF" \
    --source "$SOURCE_HEX" \
    --target "$TARGET_HEX"

sleep 1
kill -INT "$CAP_PID" 2>/dev/null || true
wait "$CAP_PID" 2>/dev/null || true
CAP_PID=

[ -s "$PCAP" ] || {
    echo "virtual target did not capture a WOL packet" >&2
    cat "$TCPDUMP_LOG" >&2 || true
    exit 4
}

python3 "$PACKET_TOOL" verify \
    --pcap "$PCAP" \
    --source "$SOURCE_HEX" \
    --target "$TARGET_HEX"
