#!/bin/sh
# Offline fake socat: consumes stdin, verifies 102 exact Magic Packet bytes,
# verifies the selected interface/socket arguments; never creates a socket.
set -eu
[ "$#" -eq 3 ] && [ "$1" = "-u" ] && [ "$2" = "-" ] || {
    echo "MOCK_REJECT_SOCAT_ARGS" >&2; exit 92
}
case "${UU_TEST_IP_SCENARIO:-}" in
    router) dest='UDP4-DATAGRAM:198.51.100.255:9,broadcast,so-bindtodevice=br-lan,bind=198.51.100.1,dontroute,shut-none' ;;
    alias) dest='UDP4-DATAGRAM:198.51.101.255:9,broadcast,so-bindtodevice=br-lan,bind=198.51.100.2,dontroute,shut-none' ;;
    nas) dest='UDP4-DATAGRAM:198.51.100.255:9,broadcast,so-bindtodevice=eth0,bind=198.51.100.11,dontroute,shut-none' ;;
    multi) dest='UDP4-DATAGRAM:198.51.100.255:9,broadcast,so-bindtodevice=br0,bind=198.51.100.2,dontroute,shut-none' ;;
    *) echo "MOCK_REJECT_UNKNOWN_SCENARIO" >&2; exit 93 ;;
esac
[ "$3" = "$dest" ] || { echo "MOCK_REJECT_SOCAT_DESTINATION" >&2; exit 94; }

hex=$(od -An -tx1 | tr -d ' \n' | tr 'abcdef' 'ABCDEF')
[ "${#hex}" -eq 204 ] || {
    echo "MOCK_REJECT_PACKET_LENGTH" >&2; exit 95
}
target_hex=${UU_TEST_EXPECT_MAC_HEX:-02AABBCCDDEE}
case "$target_hex" in
    *[!0-9A-F]*|'') echo "MOCK_REJECT_EXPECTED_MAC" >&2; exit 91 ;;
esac
[ "${#target_hex}" -eq 12 ] || { echo "MOCK_REJECT_EXPECTED_MAC_LENGTH" >&2; exit 91; }
want='FFFFFFFFFFFF'
n=0
while [ "$n" -lt 16 ]; do
    want="${want}${target_hex}"
    n=$((n+1))
done
[ "$hex" = "$want" ] || {
    echo "MOCK_REJECT_PACKET_CONTENT" >&2; exit 96
}
if [ "${UU_TEST_SOCAT_BEHAVIOR:-pass}" = "fail" ]; then
    echo "MOCK_SOCAT_FAILURE" >&2; exit 97
fi
echo "MOCK_SOCAT_PACKET_102_BYTES_VALIDATED"
