#!/bin/sh
# Fail closed: known static fixture addresses are non-secret, but a new
# private IP, real-looking MAC or token anywhere must remain detectable.
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
FILTER="$ROOT/tests/filter-remote-helper-fixtures.awk"
count=0
safe() {
    input=$1
    masked=$(printf '%s\n' "$input" | awk -f "$FILTER")
    if [ "$masked" = "$input" ]; then
        echo "FAIL: known synthetic fixture not masked" >&2; exit 1
    fi
    count=$((count+1))
}
unsafe() {
    input=$1
    token=$2
    masked=$(printf '%s\n' "$input" | awk -f "$FILTER")
    if ! printf '%s\n' "$masked" | grep -Fq "$token"; then
        echo "FAIL: real-looking identifier was suppressed" >&2; exit 1
    fi
    count=$((count+1))
}
safe 'tests/test-remote-helper-cloud.mjs:42: const a="198.51.100.40"'
safe 'tests/test-remote-helper-lan.sh:50: 255.255.255.128'
safe 'tests/test-remote-helper-loopback.py:12: HOST="127.0.0.1"'
safe 'tests/test-remote-helper-cloud.mjs:10: 02:aa:bb:cc:dd:ee'
safe 'tests/fixtures/remote-helper-ip.sh:50: 198.51.101.8'
safe "experiments/remote-helper/README.md:12: socat 1.8.0.$(printf 3)"
safe 'aabbccddeeff00112233445566778899aabbccdd:tests/test-remote-helper-cloud.mjs:40: 02:10:20:30:40:50'
unsafe 'src/program.c:1: 198.51.100.40' '198.51.100.40'
bad_ip="10.9.8.$(printf 7)"
unsafe "tests/test-remote-helper-cloud.mjs:5: fixture=$bad_ip" "$bad_ip"
bad_mac="52:54:00:11:22:$(printf 33)"
unsafe "tests/fixtures/remote-helper-ip.sh:3: mac=$bad_mac" "$bad_mac"
secret="gho_$(printf '%025d' 0)"
unsafe "tests/fixtures/remote-helper-ip.sh:8: token=$secret" "$secret"
secret2="key1=$(printf '%020d' 0)"
unsafe "tests/test-remote-helper-cloud.mjs:3: value=$secret2" "$secret2"
unsafe "tests/test-remote-helper-cloud.mjs:3: 198.51.100.2 $bad_ip" "$bad_ip"
echo "REMOTE_HELPER_SENSITIVE_FILTER_PASS count=$count"
