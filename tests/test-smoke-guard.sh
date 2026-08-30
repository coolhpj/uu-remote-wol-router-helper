#!/bin/sh

set -u

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
SMOKE="$ROOT_DIR/platforms/xiaoqiang/smoke-test.sh"

failures=0

ok() {
    printf 'ok - %s\n' "$1"
}

not_ok() {
    printf 'not ok - %s\n' "$1" >&2
    failures=$((failures + 1))
}

out=$(sh "$SMOKE" 2>&1)
rc=$?
if [ "$rc" -eq 64 ] && printf '%s' "$out" | grep 'disabled by default' >/dev/null 2>&1; then
    ok "smoke-test is disabled by default"
else
    not_ok "smoke-test is disabled by default"
fi

out2=$(UU_STAGE_DIR=/etc/not-allowed UU_RUNTIME_TEST_CONFIRM=TEMPORARY_RUNTIME_CHANGE sh "$SMOKE" 2>&1)
rc2=$?
if [ "$rc2" -eq 2 ] && printf '%s' "$out2" | grep 'Unsafe stage directory' >/dev/null 2>&1; then
    ok "unsafe stage directory is rejected before runtime changes"
else
    not_ok "unsafe stage directory is rejected before runtime changes"
fi

if [ "$failures" -ne 0 ]; then
    printf '%s test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all smoke guard tests passed\n'
