#!/bin/sh
set -eu

echo "== shell syntax =="
find . -type f -name '*.sh' -not -path './.git/*' -print | sort | while IFS= read -r file; do
    sh -n "$file"
    printf 'ok - %s\n' "$file"
done

echo "== unit / guard tests =="
for test_file in \
    tests/test-api-parser.sh \
    tests/test-channel.sh \
    tests/test-remote-helper-lan.sh \
    tests/test-remote-helper-magic.sh \
    tests/test-remote-helper-discovery.sh \
    tests/test-remote-helper-sender.sh \
    tests/test-remote-helper-sensitive-filter.sh \
    tests/test-mips-elf.sh \
    tests/test-mips-runtime-readiness.sh \
    tests/test-mips-runtime-health.sh \
    tests/test-mips-runtime-lifecycle.sh \
    tests/test-mips-persist-capacity.sh \
    tests/test-resource-advice.sh \
    tests/test-qemu-memory-metrics.sh \
    tests/test-brand-fixtures.sh \
    tests/test-mips-experimental-persist.sh \
    tests/test-mips-experimental-boot.sh \
    tests/test-mips-experimental-stop.sh \
    tests/test-evidence-marker.sh \
    tests/test-helper-cli.sh \
    tests/test-wizard.sh \
    tests/test-stage-core.sh \
    tests/test-smoke-guard.sh \
    tests/test-asuswrt-adapter.sh \
    tests/test-openwrt-adapter.sh \
    tests/test-openwrt-smoke-guard.sh \
    tests/test-openwrt-persist.sh \
    tests/test-openwrt-owned-guardian.sh \
    tests/test-xiaoqiang-runtime.sh \
    tests/test-xiaoqiang-persist.sh
 do
    sh "$test_file"
done

echo "== Remote Helper experimental offline protocol tests =="
if command -v node >/dev/null 2>&1; then
    node --test --test-reporter=spec \
        tests/test-remote-helper-cloud.mjs tests/test-remote-helper-cloud-bridge.mjs \
        tests/test-remote-helper-enrollment.mjs tests/test-remote-helper-credentials.mjs \
        tests/test-remote-helper-qr-loopback.mjs tests/test-remote-helper-room-loopback.mjs \
        tests/test-remote-helper-credential-session.mjs tests/test-remote-helper-vendor-wire.mjs
else
    echo "REMOTE_HELPER_CLOUD_CONTRACT_SKIPPED: Node.js unavailable (separate CI must enforce)"
fi

echo "== Optional real UDP loopback =="
if command -v python3 >/dev/null 2>&1; then
    python3 tests/test-remote-helper-loopback.py
else
    echo "REMOTE_HELPER_LOOPBACK_SKIPPED: python3 unavailable (separate CI must enforce)"
fi

echo "== sensitive scan =="
sh tests/scan-sensitive.sh

echo "all CI checks passed"
