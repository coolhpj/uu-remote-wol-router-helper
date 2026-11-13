#!/bin/sh
# Experimental Magic Packet encoder. Offline only: output hex text, never send packets.
set -eu
if [ "$#" -ne 1 ]; then
    echo "usage: sh magic-packet-hex.sh <target-MAC>" >&2
    exit 64
fi
awk -v original="$1" '
function fail(message) { print "REJECT_WOL_MAC: " message > "/dev/stderr"; exit 65 }
function hexval(c) { return index("0123456789ABCDEF",c)-1 }
BEGIN {
    if(original !~ /^[0-9A-Fa-f:.-]+$/) fail("invalid MAC characters")
    mac=toupper(original)
    gsub(/[:.-]/,"",mac)
    if(length(mac)!=12 || mac !~ /^[0-9A-F]+$/) fail("MAC must be six bytes")
    if(mac=="000000000000" || mac=="FFFFFFFFFFFF") fail("unicast MAC required")
    # A group/multicast destination is not a valid wake target.
    first_byte=16*hexval(substr(mac,1,1))+hexval(substr(mac,2,1))
    if(first_byte%2!=0) fail("multicast MAC rejected")
    packet="FFFFFFFFFFFF"
    for(i=1;i<=16;i++) packet=packet mac
    if(length(packet)!=204) fail("unexpected Magic Packet length")
    print packet
}' </dev/null
