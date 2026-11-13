#!/bin/sh
# Linux CI-only virtual LAN acceptance test of the unmodified WOL sender.
# All traffic stays inside two namespaces joined by a throwaway veth pair.
set -eu
[ "$(id -u)" -eq 0 ] || { echo "VIRTUAL_WOL_REQUIRES_CI_ROOT" >&2; exit 69; }
for dependency in ip socat python3 awk; do
    command -v "$dependency" >/dev/null 2>&1 || { echo "MISSING_VIRTUAL_WOL_DEPENDENCY: $dependency" >&2; exit 69; }
done
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sender="$root/experiments/remote-helper/wol-send.sh"
[ -r "$sender" ] || exit 70
work=$(mktemp -d "/tmp/uu-wol-netns.XXXXXXXX")
helper_ns="uuwolh$$"
target_ns="uuwolt$$"
helper_link="uuwha$$"
target_link="uuwta$$"
receiver_pid=""
cleanup() {
    set +e
    if [ -n "$receiver_pid" ]; then
        kill "$receiver_pid" 2>/dev/null || :
        wait "$receiver_pid" 2>/dev/null || :
    fi
    ip netns del "$helper_ns" 2>/dev/null || :
    ip netns del "$target_ns" 2>/dev/null || :
    rm -rf -- "$work"
}
trap cleanup EXIT HUP INT TERM

# Neither namespace has a default route or a route to the runner/Internet.
ip netns add "$helper_ns"
ip netns add "$target_ns"
ip link add "$helper_link" type veth peer name "$target_link"
ip link set "$helper_link" netns "$helper_ns"
ip link set "$target_link" netns "$target_ns"
ip -n "$helper_ns" link set lo up
ip -n "$target_ns" link set lo up
ip -n "$helper_ns" link set "$helper_link" name br-lan
ip -n "$target_ns" link set "$target_link" name lan0
ip -n "$helper_ns" addr add 198.51.100.1/24 dev br-lan
ip -n "$target_ns" addr add 198.51.100.40/24 dev lan0
ip -n "$helper_ns" link set br-lan up
ip -n "$target_ns" link set lan0 up
for ns in "$helper_ns" "$target_ns"; do
    if ip -n "$ns" -4 route show default | grep -q .; then
        echo "VIRTUAL_WOL_UNSAFE_DEFAULT_ROUTE" >&2
        exit 70
    fi
done

cat > "$work/recv.py" <<'PY'
import socket
import sys
from pathlib import Path

ready, report = map(Path, sys.argv[1:3])
expected = b"\xff" * 6 + bytes.fromhex("02aabbccddee") * 16
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
    sock.bind(("0.0.0.0", 9))
    sock.settimeout(5)
    ready.write_text("ready\n", encoding="ascii")
    payload, (source, _) = sock.recvfrom(1024)
    if len(payload) != 102 or payload != expected or source != "198.51.100.1":
        raise SystemExit("VIRTUAL_WOL_INVALID_MAGIC_PACKET")
    sock.settimeout(0.45)
    try:
        extra = sock.recvfrom(1024)
    except socket.timeout:
        extra = None
    if extra is not None:
        raise SystemExit("VIRTUAL_WOL_DUPLICATE_DATAGRAM")
report.write_text("VIRTUAL_NETNS_WOL_PASS count=1 bytes=102\n", encoding="ascii")
PY

ip netns exec "$target_ns" python3 -B "$work/recv.py" "$work/ready" "$work/report" &
receiver_pid=$!
attempt=0
while [ ! -f "$work/ready" ]; do
    if ! kill -0 "$receiver_pid" 2>/dev/null; then
        echo "VIRTUAL_WOL_RECEIVER_EXITED" >&2
        exit 70
    fi
    attempt=$((attempt + 1))
    [ "$attempt" -le 80 ] || { echo "VIRTUAL_WOL_RECEIVER_TIMEOUT" >&2; exit 70; }
    sleep 0.1
done

target_mac=$(printf '%s:%s:%s:%s:%s:%s' 02 aa bb cc dd ee)
UU_WOL_SEND_CONFIRM=SEND_ONE_WOL_PACKET \
    ip netns exec "$helper_ns" sh "$sender" --send \
        198.51.100.40 "$target_mac" br-lan > "$work/sender.out"
grep -q REMOTE_WOL_SOCKET_WRITE_PASS "$work/sender.out"
grep -q 'bytes_submitted: 102' "$work/sender.out"
wait "$receiver_pid"
receiver_pid=""
grep -q '^VIRTUAL_NETNS_WOL_PASS count=1 bytes=102$' "$work/report"

# Negative gates are checked inside the isolated namespace only.
if ip netns exec "$helper_ns" sh "$sender" --send \
    198.51.100.40 "$target_mac" br-lan > "$work/no-consent.out" 2>&1; then
    echo "VIRTUAL_WOL_ACCEPTED_WITHOUT_CONSENT" >&2
    exit 70
fi
grep -q REJECT_WOL_SEND "$work/no-consent.out"
if UU_WOL_SEND_CONFIRM=SEND_ONE_WOL_PACKET ip netns exec "$helper_ns" \
    sh "$sender" --send 203.0.113.40 "$target_mac" br-lan \
    > "$work/wrong-subnet.out" 2>&1; then
    echo "VIRTUAL_WOL_ACCEPTED_WRONG_SUBNET" >&2
    exit 70
fi
grep -q REJECT_WOL "$work/wrong-subnet.out"
if UU_WOL_SEND_CONFIRM=SEND_ONE_WOL_PACKET ip netns exec "$helper_ns" \
    sh "$sender" --send 198.51.100.40 "$target_mac" eth0 \
    > "$work/wrong-interface.out" 2>&1; then
    echo "VIRTUAL_WOL_ACCEPTED_WRONG_INTERFACE" >&2
    exit 70
fi
grep -q REJECT_WOL "$work/wrong-interface.out"
echo "VIRTUAL_NETNS_WOL_PASS packet_count=1 bytes=102 isolated=two_network_namespaces"
echo "VIRTUAL_NETNS_WOL_NEGATIVE_GATES_PASS consent,subnet,interface"
