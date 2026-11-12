#!/bin/sh
# Simulated one-shot WoL sender. Only fake ip and socat are visible in test PATH.
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
SENDER="$ROOT/experiments/remote-helper/wol-send.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
cp "$ROOT/tests/fixtures/remote-helper-ip.sh" "$TMP/ip"
cp "$ROOT/tests/fixtures/remote-helper-socat.sh" "$TMP/socat"
chmod 700 "$TMP/ip" "$TMP/socat"
count=0

preview() {
    scenario=$1
    shift
    output=$(UU_TEST_IP_SCENARIO="$scenario" PATH="$TMP:$PATH" sh "$SENDER" "$@" 2>&1) || {
        echo "FAIL: preview $scenario => $output" >&2; exit 1
    }
    printf '%s\n' "$output" | grep -Fq REMOTE_WOL_SEND_PREVIEW_PASS || exit 1
    printf '%s\n' "$output" | grep -Fq 'wol_packet_sent: no' || exit 1
    if printf '%s\n' "$output" | grep -Fq 'MOCK_SOCAT_'; then
        echo "FAIL: preview attempted sending" >&2; exit 1
    fi
    count=$((count+1))
}
reject() {
    scenario=$1 required=$2
    shift 2
    if output=$(UU_TEST_IP_SCENARIO="$scenario" UU_WOL_SEND_CONFIRM=SEND_ONE_WOL_PACKET PATH="$TMP:$PATH" sh "$SENDER" "$@" 2>&1); then
        echo "FAIL: unsafe send was accepted ($scenario)" >&2; exit 1
    fi
    printf '%s\n' "$output" | grep -Fq "$required" || {
        echo "FAIL: bad rejection reason ($scenario): $output" >&2; exit 1
    }
    count=$((count+1))
}
send_ok() {
    scenario=$1
    shift
    output=$(UU_TEST_IP_SCENARIO="$scenario" UU_WOL_SEND_CONFIRM=SEND_ONE_WOL_PACKET PATH="$TMP:$PATH" sh "$SENDER" --send "$@" 2>&1) || {
        echo "FAIL: synthetic send $scenario => $output" >&2; exit 1
    }
    printf '%s\n' "$output" | grep -Fq 'MOCK_SOCAT_PACKET_102_BYTES_VALIDATED' || {
        echo "FAIL: $scenario socat mock didn't validate payload" >&2; exit 1
    }
    printf '%s\n' "$output" | grep -Fq REMOTE_WOL_SOCKET_WRITE_PASS || exit 1
    count=$((count+1))
}
preview router 198.51.100.40 02:aa:bb:cc:dd:ee
preview nas 198.51.100.44 02:aa:bb:cc:dd:ee eth0
preview alias 198.51.101.8 02:aa:bb:cc:dd:ee br-lan
reject router REJECT_WOL --send 198.51.100.40 02:aa:bb:cc:dd:gg
reject router REJECT_WOL --send 198.51.101.40 02:aa:bb:cc:dd:ee
reject badroute REJECT_WOL_SEND --send 198.51.100.40 02:aa:bb:cc:dd:ee
reject routed REJECT_WOL_SEND --send 198.51.100.40 02:aa:bb:cc:dd:ee
reject noroute REJECT_WOL_SEND --send 198.51.100.40 02:aa:bb:cc:dd:ee
reject multi REJECT_WOL --send 198.51.100.40 02:aa:bb:cc:dd:ee
reject router REJECT_WOL --send 198.51.100.40 01:aa:bb:cc:dd:ee
send_ok router 198.51.100.40 02:aa:bb:cc:dd:ee
send_ok nas 198.51.100.44 02:aa:bb:cc:dd:ee eth0
send_ok alias 198.51.101.8 02:aa:bb:cc:dd:ee br-lan
if output=$(UU_TEST_IP_SCENARIO=router PATH="$TMP:$PATH" sh "$SENDER" --send 198.51.100.40 02:aa:bb:cc:dd:ee 2>&1); then
    echo "FAIL: send without explicit confirmation accepted" >&2; exit 1
fi
printf '%s\n' "$output" | grep -Fq REJECT_WOL_SEND || exit 1
count=$((count+1))
if output=$(UU_TEST_IP_SCENARIO=router UU_WOL_SEND_CONFIRM=SEND_ONE_WOL_PACKET UU_TEST_SOCAT_BEHAVIOR=fail PATH="$TMP:$PATH" sh "$SENDER" --send 198.51.100.40 02:aa:bb:cc:dd:ee 2>&1); then
    echo "FAIL: socat failed but sender reported success" >&2; exit 1
fi
printf '%s\n' "$output" | grep -Fq WOL_SEND_FAILED || exit 1
count=$((count+1))
echo "REMOTE_HELPER_WOL_SENDER_MOCK_TEST_PASS count=$count"
