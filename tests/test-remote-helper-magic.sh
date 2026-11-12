#!/bin/sh
# No networking: assert exact 102-byte Magic Packet encoding as hex.
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
ENCODER="$ROOT/experiments/remote-helper/magic-packet-hex.sh"
count=0
mac='02AABBCCDDEE'
expected='FFFFFFFFFFFF'
i=0
while [ "$i" -lt 16 ]; do
    expected="${expected}${mac}"
    i=$((i + 1))
done
for notation in '02:aa:bb:cc:dd:ee' '02-aa-bb-cc-dd-ee' '02AABBCCDDEE'; do
    actual=$(sh "$ENCODER" "$notation")
    [ "$actual" = "$expected" ] || { echo "FAIL: packet hex mismatch" >&2; exit 1; }
    [ "${#actual}" -eq 204 ] || { echo "FAIL: packet size is not 102 bytes" >&2; exit 1; }
    count=$((count + 1))
done
for invalid in '00:00:00:00:00:00' 'ff:ff:ff:ff:ff:ff' '01:aa:bb:cc:dd:ee' 'xx:aa:bb:cc:dd:ee' '02:aa:bb' '02:aa:bb:cc:dd:gg'; do
    if output=$(sh "$ENCODER" "$invalid" 2>&1); then
        echo "FAIL: accepted invalid WOL target MAC" >&2; exit 1
    fi
    printf '%s\n' "$output" | grep -Fq REJECT_WOL_MAC || { echo "FAIL: bad MAC without rejection" >&2; exit 1; }
    count=$((count + 1))
done
if sh "$ENCODER" >/dev/null 2>&1; then
    echo "FAIL: accepted missing MAC" >&2; exit 1
fi
count=$((count + 1))
echo "REMOTE_HELPER_MAGIC_PACKET_OFFLINE_TEST_PASS count=$count"
