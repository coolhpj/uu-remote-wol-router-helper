#!/bin/sh
# Fixed, synthetic iproute-style data for offline tests.
# This file is installed as a fake "ip" in an isolated temporary PATH by the tests.
if [ "$#" -eq 4 ] && [ "$1" = "-4" ] && [ "$2" = "route" ] && [ "$3" = "get" ]; then
    case "${UU_TEST_IP_SCENARIO:-}" in
        router|secondary|busyboxrouter|busyboxmulti) echo "broadcast $4 dev br-lan src 198.51.100.1" ;;
        badroute) echo "broadcast $4 dev eth0 src 203.0.113.12" ;;
        routed) echo "broadcast $4 via 198.51.100.254 dev br-lan src 198.51.100.1" ;;
        noroute) exit 96 ;;
        alias) echo "broadcast $4 dev br-lan src 198.51.100.2" ;;
        nas) echo "broadcast $4 dev eth0 src 198.51.100.11" ;;
        multi) echo "broadcast $4 dev br0 src 198.51.100.2" ;;
        *) exit 97 ;;
    esac
    exit 0
fi
# Simulate BusyBox ip without -o, returning only multiline address records.
case "${UU_TEST_IP_SCENARIO:-}" in
    busybox*)
        [ "$#" -eq 3 ] && [ "$1" = "-4" ] && [ "$2" = "addr" ] && [ "$3" = "show" ] || exit 98
        case "$UU_TEST_IP_SCENARIO" in
            busyboxrouter)
                echo "2: eth0: <UP,BROADCAST> mtu 1500"
                echo "    inet 203.0.113.12/24 brd 203.0.113.255 scope global eth0"
                echo "3: br-lan: <UP,BROADCAST> mtu 1500"
                echo "    inet 198.51.100.1/24 brd 198.51.100.255 scope global br-lan"
                ;;
            busyboxnas)
                echo "2: eth0: <UP,BROADCAST> mtu 1500"
                echo "    inet 198.51.100.11/24 brd 198.51.100.255 scope global eth0"
                ;;
            busyboxmulti)
                echo "3: br-lan: <UP,BROADCAST> mtu 1500"
                echo "    inet 198.51.100.1/24 brd 198.51.100.255 scope global br-lan"
                echo "4: br0: <UP,BROADCAST> mtu 1500"
                echo "    inet 198.51.100.2/24 brd 198.51.100.255 scope global br0"
                ;;
            busyboxbad)
                echo "3: br-lan: <UP,BROADCAST> mtu 1500"
                echo "    inet 198.51.100.1/24 scope host br-lan"
                ;;
            busyboxbroken) exit 85 ;;
        esac
        exit 0
        ;;
esac
[ "$#" -eq 6 ] && [ "$1" = "-o" ] && [ "$2" = "-4" ] && [ "$3" = "addr" ] && [ "$4" = "show" ] && [ "$5" = "scope" ] && [ "$6" = "global" ] || exit 98
case "${UU_TEST_IP_SCENARIO:-}" in
    router|badroute|noroute|routed)
        echo "2: eth0    inet 203.0.113.12/24 brd 203.0.113.255 scope global eth0"
        echo "3: br-lan    inet 198.51.100.1/24 brd 198.51.100.255 scope global br-lan"
        ;;
    nas)
        echo "2: eth0    inet 198.51.100.11/24 brd 198.51.100.255 scope global eth0"
        ;;
    alias)
        echo "4: br-lan@if7    inet 198.51.100.2/23 brd 198.51.101.255 scope global br-lan"
        ;;
    multi)
        echo "3: br-lan    inet 198.51.100.1/24 brd 198.51.100.255 scope global br-lan"
        echo "5: br0    inet 198.51.100.2/24 brd 198.51.100.255 scope global br0"
        ;;
    secondary)
        echo "3: br-lan    inet 198.51.100.1/24 brd 198.51.100.255 scope global br-lan"
        echo "3: br-lan    inet 198.51.100.2/24 brd 198.51.100.255 scope global secondary br-lan:1"
        ;;
    unknown)
        echo "2: eth0    inet 203.0.113.12/24 brd 203.0.113.255 scope global eth0"
        ;;
    invalidprefix)
        echo "3: br-lan    inet 198.51.100.1/93 brd 198.51.100.255 scope global br-lan"
        ;;
    invalidmask)
        echo "3: br-lan    inet 198.51.100.1/31 brd 198.51.100.255 scope global br-lan"
        ;;
    hostscope)
        echo "3: br-lan    inet 198.51.100.1/24 brd 198.51.100.255 scope host br-lan"
        ;;
    unsupported) exit 82 ;;
    empty) ;;
    *) exit 99 ;;
esac
