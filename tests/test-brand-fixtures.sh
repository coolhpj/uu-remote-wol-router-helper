#!/bin/sh
# Fail-closed device inventory regression: never imply that a simulated brand is installed.
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd) || exit 1
DATA="$ROOT/labs/device-fixtures/brands.tsv"
fail() { echo "not ok - $*" >&2; exit 1; }
[ -f "$DATA" ] || fail 'fixture file missing'
count=0
found=' '
while IFS='|' read -r brand model firmware arch access evidence action extra; do
    case "$brand" in ''|\#*) continue ;; esac
    [ -z "${extra:-}" ] || fail "unexpected extra column for $brand"
    [ -n "$model" ] && [ -n "$firmware" ] && [ -n "$arch" ] && [ -n "$access" ] || fail "incomplete $brand fixture"
    case "$found" in *" $brand "*) fail "duplicate $brand" ;; esac
    found="$found$brand "
    case "$evidence" in real_verified|research_only|unknown) ;; *) fail "invalid evidence $brand" ;; esac
    case "$action" in official_first|preflight_only|collect_only) ;; *) fail "fixture unlocks an unsupported action: $brand" ;; esac
    if [ "$evidence" != real_verified ]; then
        [ "$action" = collect_only ] || fail "unverified $brand fixture must be collect-only"
    fi
    if [ "$access" = unconfirmed ]; then
        [ "$action" = collect_only ] || fail "unconfirmed $brand cannot install"
    fi
    count=$((count + 1))
done < "$DATA"
[ "$count" -eq 9 ] || fail "expected 9 target brands, got $count"
for expected in ASUS Xiaomi-Redmi TP-Link NETGEAR Linksys Tenda ZTE MERCURY FAST; do
    case "$found" in *" $expected "*) ;; *) fail "missing $expected" ;; esac
done
case "$found" in *' Huawei '*|*' HUAWEI '*) fail 'excluded Huawei must not be priority target' ;; esac
echo 'ok - nine brand access fixtures are read-only and fail closed'
