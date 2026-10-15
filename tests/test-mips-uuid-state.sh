#!/bin/sh
# Offline UUID (device identity) tests. Never touch router or user credentials.
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
base="/tmp/uu-wol-helper-uuid-test-$$"
stage="$base/stage"
state="$base/state"
mkdir -p "$stage/files"
trap 'rm -rf "$base"' EXIT HUP INT TERM
UU_TEST_MODE=1
UU_MIPS_STAGE_DIR="$stage"
UU_MIPS_STATE_DIR="$state"
export UU_TEST_MODE UU_MIPS_STAGE_DIR UU_MIPS_STATE_DIR
. "$ROOT/platforms/openwrt/runtime/mips-uuid-state.sh"
fail() { echo "not ok - $1" >&2; exit 1; }

uu_uuid_restore || fail "first boot without state should be allowed"
UU_UUID_TEST_FREE_KB=100
export UU_UUID_TEST_FREE_KB
if uu_uuid_initial_capacity_guard; then fail "no state and critically low flash must block binding"; fi
UU_UUID_TEST_FREE_KB=4096
export UU_UUID_TEST_FREE_KB
uu_uuid_initial_capacity_guard || fail "normal flash budget should allow first binding"
[ ! -e "$stage/files/.uuplugin_uuid" ] || fail "first boot must not synthesize an identity"
printf 'sample-device-id-12345' > "$stage/files/.uuplugin_uuid"
uu_uuid_backup_once || fail "first identity must be captured"
[ -f "$state/.uuplugin_uuid" ] || fail "backup missing"
[ "$(stat -c %a "$state/.uuplugin_uuid")" = 600 ] || fail "credential permissions not private"
cmp -s "$stage/files/.uuplugin_uuid" "$state/.uuplugin_uuid" || fail "identity changed in backup"
rm "$stage/files/.uuplugin_uuid"
uu_uuid_restore || fail "restore after simulated power cycle"
UU_UUID_TEST_FREE_KB=100
export UU_UUID_TEST_FREE_KB
uu_uuid_initial_capacity_guard || fail "existing saved identity should remain usable during low flash"
cmp -s "$stage/files/.uuplugin_uuid" "$state/.uuplugin_uuid" || fail "restored identity mismatch"
echo "ok - first bind, save, simulated reboot and exact restore"
# The device identity must survive many consecutive clean/restart cycles.
cycle=0
while [ "$cycle" -lt 30 ]; do
    rm "$stage/files/.uuplugin_uuid"
    uu_uuid_restore || fail "restart cycle $cycle lost saved identity"
    cmp -s "$stage/files/.uuplugin_uuid" "$state/.uuplugin_uuid" || fail "restart cycle $cycle changed identity"
    cycle=$((cycle + 1))
done
echo "ok - 30 consecutive restart cycles retain identical device identity"

printf 'a-new-device-id-6789' > "$stage/files/.uuplugin_uuid"
if uu_uuid_backup_once; then fail "conflicting identity must not overwrite old binding"; fi
[ "$(cat "$state/.uuplugin_uuid")" = sample-device-id-12345 ] || fail "conflicting ID altered original"
echo "ok - conflict fails closed without rotating existing binding"

rm "$state/.uuplugin_uuid"
printf 'x' > "$state/.uuplugin_uuid"
rm "$stage/files/.uuplugin_uuid"
if uu_uuid_restore; then fail "corrupt saved identity must block launch"; fi
[ ! -e "$stage/files/.uuplugin_uuid" ] || fail "corrupt saved ID created runtime identity"
echo "ok - corrupt flash identity blocks launch"

rm "$state/.uuplugin_uuid"
ln -s /etc/passwd "$state/.uuplugin_uuid"
if uu_uuid_restore; then fail "symlink saved identity should be refused"; fi
if uu_uuid_backup_once; then fail "symlink may not be replaced"; fi
[ -L "$state/.uuplugin_uuid" ] || fail "symlink unexpectedly altered"
echo "ok - symlink identity path refused"

rm "$state/.uuplugin_uuid"
printf 'oversized' > "$stage/files/.uuplugin_uuid"
# Simulate a file beyond the bounded size, without sensitive data.
dd if=/dev/zero bs=257 count=1 of="$stage/files/.uuplugin_uuid" 2>/dev/null
if uu_uuid_backup_once; then fail "oversized identifier must not be persisted"; fi
[ ! -f "$state/.uuplugin_uuid" ] || fail "oversized backup appeared"
echo "ok - oversized identity rejected"
echo "all MIPS identity persistence tests passed"
