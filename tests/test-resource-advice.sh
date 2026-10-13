#!/bin/sh
# Simulated resource budgets only. No official binary and no router writes.
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd) || exit 1
. "$ROOT/lib/resource-advice.sh"
fail() { echo "not ok - $*" >&2; exit 1; }
check() {
    description=$1 expected=$2
    shift 2
    result=$(uu_resource_advice "$@") || fail "$description should parse"
    printf '%s\n' "$result" | grep -qx "strategy: $expected" || fail "$description ($result)"
    printf '%s\n' "$result" | grep -qx 'install_authorized: no' || fail "$description must not allow installation"
    printf '%s\n' "$result" | grep -qx 'runtime_ram_verified: no' || fail "$description cannot assert RAM health"
    echo "ok - $description"
}
# Values derived from the Y1 report and official compressed/unpacked sizes.
check 'Y1 7900KiB flash and 50MiB tmp: RAM-only advisory' ram_download_candidate 7900 50304 2726 7591
check 'one archive fits but two-version atomic update does not' ram_download_candidate 7900 50000 2726 7591
check 'dual archive room permits only a cache candidate' archive_cache_candidate 12000 50000 2726 7591
check 'sufficient space offers full-install candidate, not permission' direct_candidate 50000 50000 2726 7591
check 'low tmp headroom refuses startup advice' insufficient_tmp 50000 14000 2726 7591
check 'flash below bootstrap threshold fails closed' insufficient_flash_for_bootstrap 1024 50000 2726 7591
if uu_resource_advice 7900 unknown 2726 7591 >/dev/null 2>&1; then fail 'unknown tmp must fail'; fi
if uu_resource_advice 7900 -5 2726 7591 >/dev/null 2>&1; then fail 'negative budget must fail'; fi
if uu_resource_advice 7900 50000 2726 >/dev/null 2>&1; then fail 'missing figure must fail'; fi
echo 'all read-only resource advice tests passed'
