#!/bin/sh
# Roll back the experimental Y1 v2 BOOT SELECTOR only, without restarting the router.
# Preserve both installed app trees, cached official package and device UUID.
set -u
. "$(CDPATH= cd "$(dirname "$0")/../.." && pwd)/platforms/openwrt/persist-common.sh"
[ "${UU_MIPS_BETA_ROLLBACK_CONFIRM:-}" = RESTORE_Y1_PREVIOUS_BOOT ] || {
    echo "MIPS_BETA_ROLLBACK_DENIED" >&2; exit 64;
}
TARGET_ROOT="${UU_TARGET_ROOT:-/}"
ow_validate_target_root "$TARGET_ROOT" || exit 2
if [ "$TARGET_ROOT" = / ]; then
    [ "$(id -u 2>/dev/null)" = 0 ] || exit 3
    INIT=/etc/init.d/uu-mips-wol-helper
    OLD=/usr/lib/uu-mips-wol-helper
    NEW=/usr/lib/uu-mips-wol-helper-v2
else
    [ "${UU_TEST_MODE:-0}" = 1 ] || exit 2
    INIT="$TARGET_ROOT/etc/init.d/uu-mips-wol-helper"
    OLD="$TARGET_ROOT/usr/lib/uu-mips-wol-helper"
    NEW="$TARGET_ROOT/usr/lib/uu-mips-wol-helper-v2"
fi
BACKUP="$INIT.v1-backup"
[ -f "$BACKUP" ] && [ ! -L "$BACKUP" ] &&
    grep -qx '# managed_by=uu-remote-wol-router-helper-mips-beta' "$BACKUP" &&
    grep -qx 'PROG=/usr/lib/uu-mips-wol-helper/boot.sh' "$BACKUP" ||
    { echo "MIPS_BETA_ROLLBACK_DENIED: no trusted previous init" >&2; exit 65; }
[ -f "$INIT" ] && [ ! -L "$INIT" ] &&
    grep -qx 'PROG=/usr/lib/uu-mips-wol-helper-v2/boot.sh' "$INIT" ||
    { echo "MIPS_BETA_ROLLBACK_DENIED: active init is not v2" >&2; exit 65; }
[ -f "$OLD/install.meta" ] && [ ! -L "$OLD" ] &&
    grep -qx 'managed_by=uu-remote-wol-router-helper-mips-beta' "$OLD/install.meta" &&
    [ -f "$NEW/install.meta" ] && [ ! -L "$NEW" ] || exit 65
TMP="$INIT.rollback.$$"
[ ! -e "$TMP" ] && [ ! -L "$TMP" ] || exit 65
trap 'rm -f "$TMP"' EXIT HUP INT TERM
cp "$BACKUP" "$TMP" || exit 6
chmod 755 "$TMP" || exit 6
cmp -s "$BACKUP" "$TMP" || exit 6
mv -f "$TMP" "$INIT" || exit 6
sync
echo "MIPS_BETA_V1_INIT_RESTORED_NEXT_BOOT"
echo "MIPS_BETA_ROLLBACK_PRESERVED_UUID_AND_CACHE"
