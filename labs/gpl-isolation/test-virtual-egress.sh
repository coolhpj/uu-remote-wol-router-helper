#!/bin/sh
# GPL test companion, CI only. Never run on a NAS or physical LAN.
# A Rust unit-test binary sends the real upstream WOL datagram exclusively
# between two throwaway Linux namespaces joined by one veth pair.
set -eu

[ "$(id -u)" -eq 0 ] || { echo "VIRTUAL_GPL_WOL_NEEDS_CI_ROOT" >&2; exit 69; }
[ "$#" -eq 4 ] && [ -d "$1/.git" ] && [ -x "$4" ] || { echo "VIRTUAL_GPL_WOL_CARGO_WORKSPACE_REQUIRED" >&2; exit 69; }
upstream_dir=$1
runner_user=$2
runner_home=$3
cargo_bin=$4
[ "$(id -u "$runner_user")" -ne 0 ] || { echo "VIRTUAL_GPL_WOL_UNPRIVILEGED_RUNNER_REQUIRED" >&2; exit 69; }
[ "$(pwd -P)" = "$(cd "$upstream_dir" && pwd -P)" ] || { echo "VIRTUAL_GPL_WOL_WORKTREE_MISMATCH" >&2; exit 69; }
for dep in ip python3 grep runuser; do
    command -v "$dep" >/dev/null 2>&1 || { echo "VIRTUAL_GPL_WOL_MISSING_TOOL: $dep" >&2; exit 69; }
done
work=$(mktemp -d /tmp/gpl-wol-only-veth.XXXXXXXX)
sn="gwlS$$"
rn="gwlR$$"
sv="gwlVs$$"
rv="gwlVr$$"
receiver_pid=""
cleanup() {
    set +e
    if [ -n "$receiver_pid" ]; then
        kill "$receiver_pid" 2>/dev/null || :
        wait "$receiver_pid" 2>/dev/null || :
    fi
    ip netns del "$sn" 2>/dev/null || :
    ip netns del "$rn" 2>/dev/null || :
    rm -rf -- "$work"
}
trap cleanup EXIT HUP INT TERM

ip netns add "$sn"
ip netns add "$rn"
ip link add "$sv" type veth peer name "$rv"
ip link set "$sv" netns "$sn"
ip link set "$rv" netns "$rn"
ip -n "$sn" link set lo up
ip -n "$rn" link set lo up
ip -n "$sn" link set "$sv" name br-lan
ip -n "$rn" link set "$rv" name pc0
ip -n "$sn" addr add 198.51.100.1/24 dev br-lan
ip -n "$rn" addr add 198.51.100.40/24 dev pc0
ip -n "$sn" link set br-lan up
ip -n "$rn" link set pc0 up
# A synthetic default route is needed because the upstream GPL LAN probe
# reads /proc/net/route; its gateway is inside the equally isolated peer.
# The receiver has no default route, no host NIC and IP forwarding disabled.
ip -n "$sn" route add default via 198.51.100.40 dev br-lan
if [ -n "$(ip -n "$rn" route show default)" ]; then
    echo "VIRTUAL_GPL_WOL_UNEXPECTED_RECEIVER_ROUTE" >&2
    exit 70
fi
# The setting is namespaced, not changed on the Runner host.
ip netns exec "$rn" sysctl -qw net.ipv4.ip_forward=0
if [ "$(ip netns exec "$rn" cat /proc/sys/net/ipv4/ip_forward)" != "0" ]; then
    echo "VIRTUAL_GPL_WOL_FORWARDING_NOT_DISABLED" >&2
    exit 70
fi
echo "VIRTUAL_GPL_WOL_NETNS_PRECHECK_PASS"

cat > "$work/listener.py" <<'PY'
import select
import socket
import sys
from pathlib import Path
ready, result = map(Path, sys.argv[1:3])
expected = b"\xff" * 6 + bytes.fromhex("021122334455") * 16
ports = {}
for port in (7, 9):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("0.0.0.0", port))
    ports[s] = port
ready.write_text("READY\n", encoding="ascii")
messages = []
while True:
    readable, _, _ = select.select(list(ports), [], [], 45 if not messages else 0.5)
    if not readable:
        break
    for sock in readable:
        payload, (source, _) = sock.recvfrom(2048)
        messages.append((ports[sock], source, payload))
for sock in ports:
    sock.close()
if len(messages) != 1:
    raise SystemExit("VIRTUAL_GPL_WOL_PACKET_COUNT_FAILURE")
port, source, payload = messages[0]
if port != 9 or source != "198.51.100.1" or payload != expected:
    raise SystemExit("VIRTUAL_GPL_WOL_PACKET_OR_PORT_FAILURE")
result.write_text(
    "VIRTUAL_GPL_WOL_EGRESS_PASS packets=1 port=9 bytes=102 udp7=0\n",
    encoding="ascii",
)
PY

ip netns exec "$rn" python3 -B "$work/listener.py" "$work/ready" "$work/result" &
receiver_pid=$!
attempt=0
while [ ! -s "$work/ready" ]; do
    kill -0 "$receiver_pid" 2>/dev/null || {
        echo "VIRTUAL_GPL_WOL_RECEIVER_DIED" >&2; exit 70;
    }
    attempt=$((attempt+1))
    [ "$attempt" -lt 100 ] || { echo "VIRTUAL_GPL_WOL_RECEIVER_TIMEOUT" >&2; exit 70; }
    sleep 0.1
done

# The direct Rust unit test is launched as the unprivileged GitHub runner
# inside the sender namespace. All dependencies must already be cached:
# no other NIC, credentials, Internet connectivity or live UU host process.
ip netns exec "$sn" runuser -u "$runner_user" -- env \
    HOME="$runner_home" CARGO_HOME="$runner_home/.cargo" \
    RUSTUP_HOME="$runner_home/.rustup" CARGO_NET_OFFLINE=true UU_NO_GTK=1 \
    UU_WOL_ISOLATED_CI=1 UU_WOL_ONLY=1 UU_WOL_HELPER=1 \
    UU_REMOTE_ASSIST=0 UU_PORT_MAPPING=0 \
    UU_WOL_ALLOWED_MAC=02:11:22:33:44:55 UU_WOL_LAN_IFACE=br-lan \
    "$cargo_bin" test --offline --locked --bin uuremote-server \
    wol::tests::wol_only_ci_isolated_packet_sender -- --exact --nocapture \
        > "$work/rust-test.log" 2>&1 || {
    cat "$work/rust-test.log" >&2
    echo "VIRTUAL_GPL_WOL_RUST_SENDER_FAILURE" >&2
    exit 70
}
grep -q "1 passed; 0 failed" "$work/rust-test.log" || {
    cat "$work/rust-test.log" >&2
    echo "VIRTUAL_GPL_WOL_RUST_TEST_NO_PASS" >&2
    exit 70
}
echo "VIRTUAL_GPL_WOL_RUST_TEST_PASS"
wait "$receiver_pid"
receiver_pid=""
grep -q '^VIRTUAL_GPL_WOL_EGRESS_PASS packets=1 port=9 bytes=102 udp7=0$' "$work/result" || {
    echo "VIRTUAL_GPL_WOL_CAPTURE_REPORT_MISSING" >&2
    exit 70
}
cat "$work/result"
echo "VIRTUAL_GPL_WOL_NETWORK_ISOLATION_PASS sender_only_virtual_lan=yes"
