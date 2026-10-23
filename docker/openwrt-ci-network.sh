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
ip link set br-lan up
# This synthetic interface intentionally has no IP and no access to a home LAN.
mkdir -p /etc/config
cat > /etc/config/network <<'NETWORK'
config interface 'loopback'
    option device 'lo'
    option proto 'loopback'

config interface 'lan'
    option device 'br-lan'
    option proto 'none'
NETWORK
echo "UU_CI_SYNTHETIC_BR_LAN_READY (isolated network only)"
exec /bin/sh /opt/uu-helper/docker/entrypoint.sh probe-runtime
