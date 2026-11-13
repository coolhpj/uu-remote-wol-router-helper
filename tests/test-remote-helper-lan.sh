#!/bin/sh
# Offline-only contract tests. Never touch a NIC, UU account, Docker, or remote PC.
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/experiments/remote-helper/lan-preflight.sh"
count=0
ok() {
    label=$1 iface=$2 local_ip=$3 mask=$4 target=$5 expected=$6
    output=$(sh "$SCRIPT" "$iface" "$local_ip" "$mask" "$target" 2>&1)
    printf '%s\n' "$output" | grep -Fq REMOTE_WOL_LAN_CANDIDATE_PASS || {
        echo "FAIL: $label (no PASS)" >&2; exit 1;
    }
    printf '%s\n' "$output" | grep -Fq "$expected" || {
        echo "FAIL: $label (wrong broadcast)" >&2; exit 1;
    }
    printf '%s\n' "$output" | grep -Fq 'network_packets_sent: no' || {
        echo "FAIL: $label (not offline)" >&2; exit 1;
    }
    count=$((count+1))
}
bad() {
    label=$1
    shift
    if output=$(sh "$SCRIPT" "$@" 2>&1); then
        echo "FAIL: $label (unsafe case accepted)" >&2; exit 1
    fi
    printf '%s\n' "$output" | grep -Eq 'REJECT_|usage:' || {
        echo "FAIL: $label (missing clear rejection)" >&2; exit 1;
    }
    count=$((count+1))
}
# RFC 5737 TEST-NET, never live LAN addresses or identities.
ok /24 br-lan 198.51.100.10 255.255.255.0 198.51.100.20 'directed_broadcast: 198.51.100.255'
ok /23 br-lan 198.51.100.250 255.255.254.0 198.51.101.7 'directed_broadcast: 198.51.101.255'
ok /25 br-lan 198.51.100.129 255.255.255.128 198.51.100.201 'prefix: /25'
bad 'default WAN' wan 198.51.100.10 255.255.255.0 198.51.100.20
bad 'pppoe' pppoe-wan 198.51.100.10 255.255.255.0 198.51.100.20
bad 'loopback' lo 198.51.100.10 255.255.255.0 198.51.100.20
bad 'tunnel' wg0 198.51.100.10 255.255.255.0 198.51.100.20
bad 'unsafe interface string' 'br-lan;id' 198.51.100.10 255.255.255.0 198.51.100.20
bad 'outside LAN subnet' br-lan 198.51.100.10 255.255.255.0 198.51.101.20
bad 'invalid mask gaps' br-lan 198.51.100.10 255.0.255.0 198.51.100.20
bad 'IPv4 octal ambiguity' br-lan 198.51.100.010 255.255.255.0 198.51.100.20
bad 'broadcast as target' br-lan 198.51.100.10 255.255.255.0 198.51.100.255
bad 'network address as target' br-lan 198.51.100.10 255.255.255.0 198.51.100.0
bad 'helper equals target' br-lan 198.51.100.10 255.255.255.0 198.51.100.10
bad 'host is subnet boundary' br-lan 198.51.100.0 255.255.255.0 198.51.100.20
bad '/32 has no broadcast' br-lan 198.51.100.10 255.255.255.255 198.51.100.20
bad 'link local IP' br-lan 169.254.0.10 255.255.0.0 169.254.0.20
bad 'unsupported multicast' br-lan 239.1.2.3 255.255.255.0 239.1.2.4
bad 'missing args' br-lan 198.51.100.10
echo "REMOTE_HELPER_LAN_OFFLINE_TEST_PASS count=$count"
