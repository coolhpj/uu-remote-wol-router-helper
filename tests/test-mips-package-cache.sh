#!/bin/sh
# Cache tests use synthetic packages. No official executable or router involved.
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
base="/tmp/uu-wol-helper-cache-test-$$"
mkdir -p "$base/files" "$base/runtime"
trap 'rm -rf "$base"' EXIT HUP INT TERM
# Non-secret, compressible-but-large synthetic package data.
cp "$ROOT/scripts/stage-package.sh" "$base/files/uuplugin"
for f in xuplugin-guardian uu.conf xtables-nft-multi; do
    printf '%s\n' "$f" > "$base/files/$f"
done
tar -czf "$base/package.tar.gz" -C "$base/files" uuplugin xuplugin-guardian uu.conf xtables-nft-multi
expected=$(md5sum "$base/package.tar.gz")
expected="${expected%% *}"
UU_TEST_MODE=1
UU_MIPS_STATE_DIR="$base/state"
export UU_TEST_MODE UU_MIPS_STATE_DIR
. "$ROOT/lib/checksum.sh"
. "$ROOT/lib/archive.sh"
. "$ROOT/lib/mips-package-cache.sh"
fail() { echo "not ok - $1" >&2; exit 1; }

UU_CACHE_TEST_FREE_KB=100
export UU_CACHE_TEST_FREE_KB
if uu_cache_try_store "$base/package.tar.gz" "$expected"; then fail "low space must block cache write"; fi
[ ! -e "$base/state/uu.tar.gz" ] || fail "low-space cache unexpectedly exists"
unset UU_CACHE_TEST_FREE_KB
uu_cache_try_store "$base/package.tar.gz" "$expected" || fail "first cache store"
[ -f "$base/state/uu.tar.gz" ] || fail "cache missing"
uu_cache_try_restore "$base/runtime/uu.tar.gz" "$expected" || fail "validated cache restore"
cmp -s "$base/package.tar.gz" "$base/runtime/uu.tar.gz" || fail "restored bytes differ"
echo "ok - constrained flash first store and verified cache hit"

# Updating with insufficient flash must leave the old verified cache intact.
oldhash=$(md5sum "$base/state/uu.tar.gz")
UU_CACHE_TEST_FREE_KB=100
export UU_CACHE_TEST_FREE_KB
printf 'changed fixture\n' >> "$base/files/uu.conf"
tar -czf "$base/updated.tar.gz" -C "$base/files" uuplugin xuplugin-guardian uu.conf xtables-nft-multi
newhash=$(md5sum "$base/updated.tar.gz")
newhash="${newhash%% *}"
if uu_cache_try_store "$base/updated.tar.gz" "$newhash"; then fail "insufficient free flash must block update"; fi
[ "$(md5sum "$base/state/uu.tar.gz")" = "$oldhash" ] || fail "old cache modified on update failure"
echo "ok - insufficient update space retains original archive"

# A mismatched or corrupt cache must never be served.
if uu_cache_try_restore "$base/runtime/other.tar.gz" "$newhash"; then fail "old cache must not masquerade as new release"; fi
unset UU_CACHE_TEST_FREE_KB
uu_cache_try_store "$base/updated.tar.gz" "$newhash" || fail "atomic update"
uu_cache_try_restore "$base/runtime/updated.tar.gz" "$newhash" || fail "updated cache should verify"
printf 'damage' >> "$base/state/uu.tar.gz"
if uu_cache_try_restore "$base/runtime/corrupt.tar.gz" "$newhash"; then fail "corrupt archive must be rejected"; fi
[ ! -e "$base/runtime/corrupt.tar.gz" ] || fail "corrupt bytes were served"
echo "ok - mismatched, updated and corrupted cache behavior"

rm "$base/state/uu.tar.gz"
ln -s /etc/passwd "$base/state/uu.tar.gz"
if uu_cache_try_restore "$base/runtime/link.tar.gz" "$newhash"; then fail "symlink cache is not safe"; fi
if uu_cache_try_store "$base/updated.tar.gz" "$newhash"; then fail "symlink cache must not be overwritten"; fi
[ -L "$base/state/uu.tar.gz" ] || fail "symlink altered"
echo "ok - symlink cache refused"
# A plain source checkout cannot write router flash by setting one flag.
if UU_TEST_MODE=0 UU_MIPS_ENABLE_CACHE=1 sh "$ROOT/scripts/stage-package.sh" openwrt-mipsel >/dev/null 2>&1; then
    fail "source-checkout cache activation must fail before any download"
fi
echo "ok - unowned standalone MIPS stage cannot enable flash cache"
echo "all MIPS package cache tests passed"
