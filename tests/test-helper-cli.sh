#!/bin/sh

set -u

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
HELPER="$ROOT_DIR/uu-helper.sh"

failures=0

ok() {
    printf 'ok - %s\n' "$1"
}

not_ok() {
    printf 'not ok - %s\n' "$1" >&2
    failures=$((failures + 1))
}

help_output=$(sh "$HELPER" help 2>&1)
help_rc=$?
if [ "$help_rc" -eq 0 ] && printf '%s' "$help_output" | grep 'diagnose' >/dev/null 2>&1; then
    ok "help lists diagnose"
else
    not_ok "help lists diagnose"
fi

invalid_output=$(sh "$HELPER" definitely-not-a-command 2>&1)
invalid_rc=$?
if [ "$invalid_rc" -eq 64 ] && printf '%s' "$invalid_output" | grep 'Unknown command' >/dev/null 2>&1; then
    ok "unknown command fails safely"
else
    not_ok "unknown command fails safely"
fi

collect_output=$(sh "$HELPER" collect-info 2>&1)
collect_rc=$?
if [ "$collect_rc" -eq 0 ] && printf '%s' "$collect_output" | grep 'mode: read-only' >/dev/null 2>&1; then
    ok "collect-info remains read-only"
else
    not_ok "collect-info remains read-only"
fi

if [ "$failures" -ne 0 ]; then
    printf '%s test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all helper CLI tests passed\n'
