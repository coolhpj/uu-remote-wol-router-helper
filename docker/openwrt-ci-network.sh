#!/bin/sh
# CI-only synthetic OpenWrt LAN fixture. Do not include in the production image.
# Invoke exclusively from an isolated Docker bridge with NET_ADMIN available
# only inside the container network namespace.
set -eu
[ "${UU_CI_ISOLATED_NETWORK:-}" = 1 ] || {
    echo "UU_CI_LAN_FIXTURE_DENIED: isolated CI confirmation missing" >&2
    exit 66
}
command -v ip >/dev/null 2>&1 || {
    echo "UU_CI_LAN_FIXTURE_UNAVAILABLE: ip utility missing" >&2
    exit 4
}
[ ! -e /sys/class/net/br-lan ] || {
    echo "UU_CI_LAN_FIXTURE_DENIED: br-lan already exists" >&2
    exit 65
}
ip link add br-lan type bridge || {
    echo "UU_CI_LAN_FIXTURE_UNAVAILABLE: bridge creation denied" >&2
    exit 4
}
ip addr add 198.51.100.2/24 dev br-lan
ip link set br-lan up
# TEST-NET-2 addresses are synthetic fixtures, never user LAN defaults.
mkdir -p /etc/config
cat > /etc/config/network <<'NETWORK'
config interface 'loopback'
    option device 'lo'
    option proto 'static'
    option ipaddr '127.0.0.1'
    option netmask '255.0.0.0'

config interface 'lan'
    option device 'br-lan'
    option proto 'static'
    option ipaddr '198.51.100.2'
    option netmask '255.255.255.0'
NETWORK
echo "UU_CI_SYNTHETIC_BR_LAN_READY (isolated network only)"
exec /bin/sh /opt/uu-helper/docker/entrypoint.sh probe-runtime
