#!/bin/sh

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd) || exit 1
# shellcheck source=../lib/netease-api.sh
. "$SCRIPT_DIR/../lib/netease-api.sh"

failures=0

ok() {
    printf 'ok - %s\n' "$1"
}

fail() {
    printf 'not ok - %s\n' "$1"
    failures=$((failures + 1))
}

assert_eq() {
    name="$1"
    expected="$2"
    actual="$3"
    if [ "$expected" = "$actual" ]; then
        ok "$name"
    else
        printf '  expected: %s\n' "$expected"
        printf '  actual:   %s\n' "$actual"
        fail "$name"
    fi
}

fixture_reordered='{"url_bak":"https://backup.example/uuplugin/openwrt-aarch64/v99.1/uu.tar.gz","status":"ok","url":"https://example.invalid/uuplugin/openwrt-aarch64/v99.1/uu.tar.gz?key1=a&key2=b","md5":"0123456789abcdef0123456789abcdef"}'
if uu_api_parse "$fixture_reordered"; then
    ok "parse reordered keys"
else
    fail "parse reordered keys"
fi
assert_eq "preserve URL query string" \
    'https://example.invalid/uuplugin/openwrt-aarch64/v99.1/uu.tar.gz?key1=a&key2=b' \
    "$UU_API_URL"
assert_eq "extract version from URL" "v99.1" "$UU_API_VERSION"
assert_eq "parse backup URL independently" \
    'https://backup.example/uuplugin/openwrt-aarch64/v99.1/uu.tar.gz' \
    "$UU_API_URL_BAK"

fixture_spaces='{ "status" : "ok", "md5" : "ABCDEF0123456789ABCDEF0123456789", "url" : "http://example.invalid/x/v1.2.3/uu.tar.gz" }'
if uu_api_parse "$fixture_spaces"; then
    ok "parse whitespace and uppercase MD5"
else
    fail "parse whitespace and uppercase MD5"
fi
assert_eq "normalize MD5 to lowercase" \
    "abcdef0123456789abcdef0123456789" \
    "$UU_API_MD5"
assert_eq "missing backup URL is allowed" "" "$UU_API_URL_BAK"

fixture_bad_md5='{"status":"ok","md5":"not-an-md5","url":"https://example.invalid/x/v1/uu.tar.gz"}'
if uu_api_parse "$fixture_bad_md5"; then
    fail "reject invalid MD5"
else
    ok "reject invalid MD5"
fi

fixture_bad_status='{"status":"error","md5":"0123456789abcdef0123456789abcdef","url":"https://example.invalid/x/v1/uu.tar.gz"}'
if uu_api_parse "$fixture_bad_status"; then
    fail "reject non-ok API status"
else
    ok "reject non-ok API status"
fi

fixture_bad_url='{"status":"ok","md5":"0123456789abcdef0123456789abcdef","url":"file:///tmp/uu.tar.gz"}'
if uu_api_parse "$fixture_bad_url"; then
    fail "reject non-http download URL"
else
    ok "reject non-http download URL"
fi

if uu_api_validate_channel 'openwrt-aarch64'; then
    ok "accept normal channel"
else
    fail "accept normal channel"
fi

if uu_api_validate_channel 'openwrt-aarch64;rm'; then
    fail "reject unsafe channel"
else
    ok "reject unsafe channel"
fi

if [ "$failures" -ne 0 ]; then
    printf '%s\n' "$failures test(s) failed"
    exit 1
fi

printf 'all tests passed\n'
