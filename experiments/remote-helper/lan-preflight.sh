#!/bin/sh
# Experimental, offline-only LAN / WoL target validator.
# No system inspection, cloud requests, network packets, files, or privileged actions.
# Never infer a router's LAN from the default IPv4 route.
set -eu

if [ "$#" -ne 4 ]; then
    echo "usage: sh lan-preflight.sh <LAN-interface> <LAN-IPv4> <netmask> <target-IPv4>" >&2
    exit 64
fi

interface=$1
local_ip=$2
mask=$3
target_ip=$4

case "$interface" in
    ''|*[!a-zA-Z0-9_.:-]*|lo|lo[0-9]*|wan|wan[0-9]*|pppoe*|tun*|tap*|wg*|tailscale*|docker*|veth*)
        echo "REJECT_INTERFACE: explicit LAN interface required (no loopback, WAN, tunnel or Docker bridge)" >&2
        exit 65 ;;
esac

awk -v iface="$interface" -v source_ip="$local_ip" -v mask="$mask" -v target_ip="$target_ip" '
function fail(message) { print "REJECT_LAN_CANDIDATE: " message > "/dev/stderr"; exit 65 }
function ip4(text, a,   n,i) {
    n=split(text,a,".")
    if(n!=4) return 0
    for(i=1;i<=4;i++) {
        if(a[i]!~/^[0-9]+$/ || a[i] ~ /^0[0-9]+$/ || length(a[i])>3) return 0
        a[i]+=0
        if(a[i]<0 || a[i]>255) return 0
    }
    return 1
}
function join4(a) { return a[1]"."a[2]"."a[3]"."a[4] }
BEGIN {
    if(!ip4(source_ip,src) || !ip4(mask,netmask) || !ip4(target_ip,tgt)) fail("invalid IPv4 or netmask notation")
    if(src[1]==0 || src[1]==127 || src[1]>=224 || (src[1]==169 && src[2]==254)) fail("unsupported local IPv4 address")
    if(tgt[1]==0 || tgt[1]==127 || tgt[1]>=224 || (tgt[1]==169 && tgt[2]==254)) fail("unsupported target IPv4 address")
    # Require a contiguous netmask; /31 and /32 do not provide a WoL broadcast network.
    prefix=0; partial=0
    for(i=1;i<=4;i++) {
        oct=netmask[i]
        bits=-1
        if(oct==255) bits=8
        else if(oct==254) bits=7
        else if(oct==252) bits=6
        else if(oct==248) bits=5
        else if(oct==240) bits=4
        else if(oct==224) bits=3
        else if(oct==192) bits=2
        else if(oct==128) bits=1
        else if(oct==0) bits=0
        if(bits<0 || (partial && bits>0)) fail("noncontiguous subnet mask")
        prefix+=bits
        if(bits<8) partial=1
    }
    if(prefix<8 || prefix>30) fail("unsupported WoL subnet prefix")
    for(i=1;i<=4;i++) {
        block=256-netmask[i]
        network[i]=int(src[i]/block)*block
        directed[i]=network[i]+block-1
        if(tgt[i]<network[i] || tgt[i]>directed[i]) fail("target is outside LAN subnet")
    }
    if(join4(tgt)==join4(src)) fail("target is the helper host")
    if(join4(tgt)==join4(network) || join4(tgt)==join4(directed)) fail("target is subnet boundary or broadcast")
    if(join4(src)==join4(network) || join4(src)==join4(directed)) fail("helper IP is subnet boundary or broadcast")
    print "REMOTE_WOL_LAN_CANDIDATE_PASS"
    print "lan_interface: " iface
    print "prefix: /" prefix
    print "directed_broadcast: " join4(directed)
    print "network_packets_sent: no"
    print "device_registration_attempted: no"
}' </dev/null
