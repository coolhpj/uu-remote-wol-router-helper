#!/bin/sh
# Exercise EXACT executable ownership with two live look-alike processes.
# No router/service files are touched. Tests run only in disposable /tmp.
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd) || exit 1
helper="$ROOT/platforms/openwrt/runtime/stop-owned-guardian.sh"
init="$ROOT/platforms/openwrt/runtime/uu-wol-helper.init"
test_dir="/tmp/uu-wol-helper-test-$$"
owned="$test_dir/managed/xuplugin-guardian"
foreign="$test_dir/unrelated/xuplugin-guardian"
owned_pid=''
foreign_pid=''
cleanup() {
    for pid in "$owned_pid" "$foreign_pid"; do
        [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    done
    for pid in "$owned_pid" "$foreign_pid"; do
        [ -n "$pid" ] && wait "$pid" 2>/dev/null || true
    done
    rm -rf "$test_dir"
}
trap cleanup EXIT HUP INT TERM
fail() { echo "not ok - $*" >&2; exit 1; }
[ -f "$helper" ] || fail 'missing helper'
! grep -Eq '(^|[[:space:]])killall[[:space:]]' "$init" || fail 'init must not killall by basename'
mkdir -p "$test_dir/managed" "$test_dir/unrelated"
# Avoid renaming GNU coreutils multicall 'sleep' (it refuses unknown argv[0]
# on newer GitHub runners). A copied POSIX shell stays alive in a while loop
# and still exposes the exact mock /proc/PID/exe paths we need to verify.
fixture_shell=$(command -v sh) || exit 1
cp "$fixture_shell" "$owned"
cp "$fixture_shell" "$foreign"
chmod 0755 "$owned" "$foreign"

# Confirm an untrusted caller cannot retarget the production helper.
if UU_TEST_GUARDIAN_PATH="$owned" sh "$helper" >/dev/null 2>&1; then
    fail 'production override must be refused'
fi
if UU_TEST_MODE=1 UU_TEST_GUARDIAN_PATH=/tmp/foreign/xuplugin-guardian sh "$helper" >/dev/null 2>&1; then
    fail 'test path outside owned fixture prefix must be refused'
fi

"$owned" -c 'while :; do sleep 1; done' >/dev/null 2>&1 &
owned_pid=$!
"$foreign" -c 'while :; do sleep 1; done' >/dev/null 2>&1 &
foreign_pid=$!
sleep 1
[ "$(readlink "/proc/$owned_pid/exe")" = "$owned" ] || fail 'owned fixture executable mismatch'
[ "$(readlink "/proc/$foreign_pid/exe")" = "$foreign" ] || fail 'foreign fixture executable mismatch'
UU_TEST_MODE=1 UU_TEST_GUARDIAN_PATH="$owned" sh "$helper" |
    grep -qx GUARDIAN_OWNED_STOP_PASS || fail 'owned stop did not complete'
wait "$owned_pid" 2>/dev/null || true
[ ! -e "/proc/$owned_pid/exe" ] || fail 'owned fixture still executing'
kill -0 "$foreign_pid" 2>/dev/null || fail 'foreign process was terminated'
[ "$(readlink "/proc/$foreign_pid/exe")" = "$foreign" ] || fail 'foreign process executable changed'
echo 'ok - stop only the managed guardian; preserve unrelated same-name processes'
