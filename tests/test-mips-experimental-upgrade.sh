#!/bin/sh
# Host-only simulation of v1 -> v2 on-next-boot upgrade and rollback.
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
base="/tmp/uu-wol-helper-root-upgrade-test-$$"
app="$base/usr/lib/uu-mips-wol-helper"
v2="$base/usr/lib/uu-mips-wol-helper-v2"
init="$base/etc/init.d/uu-mips-wol-helper"
stage="$base/stage"
state="$base/state"
mkdir -p "$app" "$(dirname "$init")" "$stage/files"
trap 'rm -rf "$base" "/tmp/uu-wol-helper-root-upgrade-absent-$$" "/tmp/uu-wol-helper-root-upgrade-v2-test-$$"' EXIT HUP INT TERM
cp "$ROOT/platforms/openwrt/runtime/mips-experimental.init" "$init"
printf 'managed_by=uu-remote-wol-router-helper-mips-beta\nmodel=Lenovo Y1\n' > "$app/install.meta"
printf 'legacy bootstrap kept as rollback\n' > "$app/boot.sh"
printf 'known-router-id-before-reboot' > "$stage/files/.uuplugin_uuid"
UU_TEST_MODE=1
UU_TARGET_ROOT="$base"
UU_MIPS_STAGE_DIR="$stage"
UU_MIPS_STATE_DIR="$state"
export UU_TEST_MODE UU_TARGET_ROOT UU_MIPS_STAGE_DIR UU_MIPS_STATE_DIR
fail() { echo "not ok - $1" >&2; exit 1; }

if sh "$ROOT/platforms/openwrt/mips-experimental-upgrade.sh" >/dev/null 2>&1; then fail "upgrade without explicit opt-in"; fi
[ ! -e "$v2" ] && [ ! -e "$state/.uuplugin_uuid" ] || fail "denied upgrade made changes"
echo "ok - default upgrade blocked"

out=$(UU_MIPS_BETA_UPGRADE_CONFIRM=I_ACCEPT_Y1_IDENTITY_SAFE_UPGRADE sh "$ROOT/platforms/openwrt/mips-experimental-upgrade.sh" 2>&1) || {
    echo "$out" >&2
    fail "upgrade with live identifier should succeed"
}
[ -f "$v2/boot.sh" ] && [ -f "$v2/uuid-watch.sh" ] && [ -f "$v2/lib/mips-package-cache.sh" ] || fail "v2 tree incomplete"
grep -qx 'PROG=/usr/lib/uu-mips-wol-helper-v2/boot.sh' "$init" || fail "v2 init missing"
grep -qx 'PROG=/usr/lib/uu-mips-wol-helper/boot.sh' "$init.v1-backup" || fail "old init backup missing"
cmp -s "$state/.uuplugin_uuid" "$stage/files/.uuplugin_uuid" || fail "old identity not rescued"
grep -q 'legacy bootstrap kept' "$app/boot.sh" || fail "old app modified"
echo "ok - identity captured before atomic boot selector switch; old tree intact"

if UU_MIPS_BETA_UPGRADE_CONFIRM=I_ACCEPT_Y1_IDENTITY_SAFE_UPGRADE sh "$ROOT/platforms/openwrt/mips-experimental-upgrade.sh" >/dev/null 2>&1; then fail "repeat upgrade must refuse"; fi
[ -f "$init.v1-backup" ] || fail "repeat upgrade modified backup"
echo "ok - repeat upgrade refused"

if UU_MIPS_BETA_UNINSTALL_CONFIRM=REMOVE_LENOVO_Y1_BETA_SERVICE sh "$ROOT/platforms/openwrt/mips-experimental-uninstall.sh" >/dev/null 2>&1; then
    fail "legacy uninstaller must not leave v2 orphaned"
fi
[ -f "$v2/boot.sh" ] && [ -f "$app/install.meta" ] || fail "legacy uninstall touched upgraded files"
echo "ok - legacy uninstaller refuses v2 installation"

UU_MIPS_BETA_ROLLBACK_CONFIRM=RESTORE_Y1_PREVIOUS_BOOT sh "$ROOT/platforms/openwrt/mips-experimental-upgrade-rollback.sh" >/dev/null || fail "rollback failed"
grep -qx 'PROG=/usr/lib/uu-mips-wol-helper/boot.sh' "$init" || fail "rollback did not restore old boot selector"
[ -f "$v2/boot.sh" ] && [ -f "$state/.uuplugin_uuid" ] || fail "rollback deleted evidence or identity"
echo "ok - rollback restores v1 selector and retains v2 and identifier"

# No live ID and no saved ID -> fail closed; old installation stays untouched.
missing="/tmp/uu-wol-helper-root-upgrade-absent-$$"
mkdir -p "$missing/usr/lib/uu-mips-wol-helper" "$missing/etc/init.d"
cp "$app/install.meta" "$missing/usr/lib/uu-mips-wol-helper/install.meta"
cp "$init" "$missing/etc/init.d/uu-mips-wol-helper"
if UU_TARGET_ROOT="$missing" UU_MIPS_STATE_DIR="$base/state-absent" UU_MIPS_STAGE_DIR="$base/stage-absent" UU_MIPS_BETA_UPGRADE_CONFIRM=I_ACCEPT_Y1_IDENTITY_SAFE_UPGRADE sh "$ROOT/platforms/openwrt/mips-experimental-upgrade.sh" >/dev/null 2>&1; then
    fail "missing legacy identity should block upgrade"
fi
[ ! -e "$missing/usr/lib/uu-mips-wol-helper-v2" ] || fail "missing identity changed install"
echo "ok - missing original identity blocks upgrade"

# Verify both supported service selectors: upgraded v2 and rolled-back v1.
# Clone the managed test trees before the first uninstall so cases stay isolated.
replay="/tmp/uu-wol-helper-root-upgrade-v2-test-$$"
mkdir -p "$replay/usr/lib" "$replay/etc/init.d" "$replay/state"
cp -R "$app" "$replay/usr/lib/uu-mips-wol-helper"
cp -R "$v2" "$replay/usr/lib/uu-mips-wol-helper-v2"
cp "$init.v1-backup" "$replay/etc/init.d/uu-mips-wol-helper.v1-backup"
sed 's|/usr/lib/uu-mips-wol-helper/|/usr/lib/uu-mips-wol-helper-v2/|g' \
    "$ROOT/platforms/openwrt/runtime/mips-experimental.init" > "$replay/etc/init.d/uu-mips-wol-helper"
cp "$state/.uuplugin_uuid" "$replay/state/.uuplugin_uuid"
printf 'nonsecret synthetic archive\n' > "$replay/state/uu.tar.gz"

if sh "$ROOT/platforms/openwrt/mips-experimental-v2-uninstall.sh" >/dev/null 2>&1; then
    fail "v2 uninstall without separate opt-in should be denied"
fi
UU_TARGET_ROOT="$replay" UU_MIPS_STATE_DIR="$replay/state" \
UU_MIPS_BETA_V2_UNINSTALL_CONFIRM=REMOVE_Y1_V2_AND_PRESERVE_IDENTITY sh \
    "$ROOT/platforms/openwrt/mips-experimental-v2-uninstall.sh" >/dev/null || fail "active v2 uninstall failed"
[ ! -e "$replay/usr/lib/uu-mips-wol-helper-v2" ] && [ ! -e "$replay/usr/lib/uu-mips-wol-helper" ] &&
    [ ! -e "$replay/etc/init.d/uu-mips-wol-helper" ] && [ -f "$replay/state/.uuplugin_uuid" ] || fail "active v2 uninstall did not preserve identity or remove artifacts"
echo "ok - active v2 uninstall removes managed files but preserves UUID"

# The earlier rollback left v1 selected, with both owned trees still present.
# The dedicated v2 uninstaller must handle this state, too.
grep -qx 'PROG=/usr/lib/uu-mips-wol-helper/boot.sh' "$init" || fail "rollback selector changed unexpectedly"
printf 'nonsecret synthetic archive\n' > "$state/uu.tar.gz"
UU_MIPS_BETA_V2_UNINSTALL_CONFIRM=REMOVE_Y1_V2_AND_PRESERVE_IDENTITY sh \
    "$ROOT/platforms/openwrt/mips-experimental-v2-uninstall.sh" >/dev/null || fail "rolled-back v1 uninstall failed"
[ ! -e "$v2" ] && [ ! -e "$app" ] && [ ! -e "$init" ] && [ ! -e "$init.v1-backup" ] || fail "rolled-back uninstall left executable artifacts"
[ ! -e "$state/uu.tar.gz" ] && [ -f "$state/.uuplugin_uuid" ] || fail "rolled-back uninstall did not preserve ID or left compressed archive"
echo "ok - upgrade then rollback then uninstall succeeds with UUID retained"
echo "all MIPS beta upgrade/rollback tests passed"
