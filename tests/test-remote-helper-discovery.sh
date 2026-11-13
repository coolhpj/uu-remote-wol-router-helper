#!/bin/sh
# Read-only LAN-discovery contract tests via synthetic ip output.
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
DISC="$ROOT/experiments/remote-helper/lan-discover.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
cp "$ROOT/tests/fixtures/remote-helper-ip.sh" "$TMP/ip"
chmod 700 "$TMP/ip"
count=0
ok() {
    scenario=$1 expected=$2
    shift 2
    result=$(UU_TEST_IP_SCENARIO="$scenario" PATH="$TMP:$PATH" sh "$DISC" "$@" 2>&1) || {
        echo "FAIL: $scenario expected valid but failed: $result" >&2; exit 1;
    }
    printf '%s\n' "$result" | grep -Fq 'REMOTE_WOL_LAN_DISCOVERY_PASS' || {
        echo "FAIL: $scenario discovery not confirmed" >&2; exit 1;
    }
    printf '%s\n' "$result" | grep -Fq "$expected" || {
        echo "FAIL: $scenario unexpected target LAN details" >&2; exit 1;
    }
    printf '%s\n' "$result" | grep -Fq 'wol_packet_sent: no' || {
        echo "FAIL: $scenario must be read-only" >&2; exit 1;
    }
    count=$((count+1))
}
bad() {
    scenario=$1
    shift
    if result=$(UU_TEST_IP_SCENARIO="$scenario" PATH="$TMP:$PATH" sh "$DISC" "$@" 2>&1); then
        echo "FAIL: $scenario unsafe case accepted" >&2; exit 1
    fi
    printf '%s\n' "$result" | grep -Eq 'REJECT_|LAN_INSPECTION_UNAVAILABLE' || {
        echo "FAIL: $scenario missing fail-closed reason: $result" >&2; exit 1
    }
    count=$((count+1))
}

ok router 'lan_interface: br-lan' 198.51.100.40
ok router 'directed_broadcast: 198.51.100.255' 198.51.100.40 br-lan
ok nas 'lan_interface: eth0' 198.51.100.44 eth0
ok alias 'directed_broadcast: 198.51.101.255' 198.51.101.8 br-lan
ok multi 'lan_interface: br0' 198.51.100.40 br0
ok busyboxrouter 'lan_interface: br-lan' 198.51.100.40
ok busyboxrouter 'directed_broadcast: 198.51.100.255' 198.51.100.40 br-lan
ok busyboxnas 'lan_interface: eth0' 198.51.100.44 eth0
bad busyboxnas 198.51.100.44
bad busyboxmulti 198.51.100.40
bad busyboxbad 198.51.100.40
bad busyboxbroken 198.51.100.40
bad nas 198.51.100.44
bad unknown 203.0.113.22
bad router 203.0.113.22
bad multi 198.51.100.40
bad secondary 198.51.100.40
bad unsupported 198.51.100.40
bad empty 198.51.100.40
bad hostscope 198.51.100.40
bad invalidprefix 198.51.100.40
bad invalidmask 198.51.100.40
bad router 198.51.101.40
bad router 198.51.100.255
bad router 198.51.100.1
bad router 198.51.100.abc
bad router 198.51.100.40 'br-lan;id'
echo "REMOTE_HELPER_LAN_DISCOVERY_OFFLINE_TEST_PASS count=$count"
