#!/bin/sh

set -u

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/lib/download.sh"
. "$ROOT_DIR/lib/archive.sh"

failures=0
TMP_BASE="/tmp/uu-wol-helper-test-stage-$$"
SRC="$TMP_BASE/src"
GOOD="$TMP_BASE/good.tar.gz"
MISSING="$TMP_BASE/missing.tar.gz"

cleanup() {
    rm -rf "$TMP_BASE"
}
trap cleanup EXIT HUP INT TERM

ok() {
    printf 'ok - %s\n' "$1"
}

not_ok() {
    printf 'not ok - %s\n' "$1" >&2
    failures=$((failures + 1))
}

redacted=$(uu_redact_url 'https://example.invalid/uu.tar.gz?key1=abc&key2=def')
if [ "$redacted" = 'https://example.invalid/uu.tar.gz?<redacted>' ]; then
    ok "download URL query is redacted"
else
    not_ok "download URL query is redacted"
fi

mkdir -p "$SRC"
: > "$SRC/uuplugin"
: > "$SRC/xuplugin-guardian"
printf 'version=v-test\n' > "$SRC/uu.conf"
: > "$SRC/xtables-nft-multi"

tar -czf "$GOOD" -C "$SRC" uuplugin xuplugin-guardian uu.conf xtables-nft-multi
if uu_validate_uu_package "$GOOD"; then
    ok "valid UU package structure is accepted"
else
    not_ok "valid UU package structure is accepted"
fi

rm -f "$SRC/xtables-nft-multi"
tar -czf "$MISSING" -C "$SRC" uuplugin xuplugin-guardian uu.conf
if uu_validate_uu_package "$MISSING" >/dev/null 2>&1; then
    not_ok "missing required package member is rejected"
else
    ok "missing required package member is rejected"
fi

if [ "$failures" -ne 0 ]; then
    printf '%s test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all stage core tests passed\n'
