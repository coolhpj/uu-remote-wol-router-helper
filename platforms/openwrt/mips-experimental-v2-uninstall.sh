#!/bin/sh
# Lenovo Y1 v2 experimental uninstall; retain original UUID for future recovery.
set -u
ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/../.." && pwd) || exit 1
. "$ROOT_DIR/platforms/openwrt/persist-common.sh"
[ "${UU_MIPS_BETA_V2_UNINSTALL_CONFIRM:-}" = REMOVE_Y1_V2_AND_PRESERVE_IDENTITY ] || {
    echo "MIPS_V2_UNINSTALL_DENIED: explicit confirmation required" >&2
    exit 64
}
TARGET_ROOT="${UU_TARGET_ROOT:-/}"
ow_validate_target_root "$TARGET_ROOT" || exit 2
if [ "$TARGET_ROOT" = / ]; then
    [ "$(id -u 2>/dev/null || echo 1)" = 0 ] || exit 3
    INIT=/etc/init.d/uu-mips-wol-helper
    OLD=/usr/lib/uu-mips-wol-helper
    NEW=/usr/lib/uu-mips-wol-helper-v2
    STATE=/etc/uu-mips-wol-helper
else
    [ "${UU_TEST_MODE:-0}" = 1 ] || exit 2
    INIT="$TARGET_ROOT/etc/init.d/uu-mips-wol-helper"
    OLD="$TARGET_ROOT/usr/lib/uu-mips-wol-helper"
    NEW="$TARGET_ROOT/usr/lib/uu-mips-wol-helper-v2"
    STATE="${UU_MIPS_STATE_DIR:-$TARGET_ROOT/etc/uu-mips-wol-helper}"
fi
BACKUP="$INIT.v1-backup"
owned_app() {
    [ -d "$1" ] && [ ! -L "$1" ] &&
        [ -f "$1/install.meta" ] && [ ! -L "$1/install.meta" ] &&
        grep -qx 'managed_by=uu-remote-wol-router-helper-mips-beta' "$1/install.meta"
}
owned_app "$OLD" && owned_app "$NEW" ||
    { echo "MIPS_V2_UNINSTALL_DENIED: unowned application directories" >&2; exit 65; }
[ -f "$INIT" ] && [ ! -L "$INIT" ] &&
    grep -qx '# managed_by=uu-remote-wol-router-helper-mips-beta' "$INIT" &&
    { grep -qx 'PROG=/usr/lib/uu-mips-wol-helper-v2/boot.sh' "$INIT" ||
      grep -qx 'PROG=/usr/lib/uu-mips-wol-helper/boot.sh' "$INIT"; } || {
        echo "MIPS_V2_UNINSTALL_DENIED: unrecognized v1/v2 boot selector" >&2
        exit 65
    }
[ -f "$BACKUP" ] && [ ! -L "$BACKUP" ] &&
    grep -qx '# managed_by=uu-remote-wol-router-helper-mips-beta' "$BACKUP" &&
    grep -qx 'PROG=/usr/lib/uu-mips-wol-helper/boot.sh' "$BACKUP" || exit 65
# No symlink may redirect persistent identifier or archived binaries.
[ ! -L "$STATE" ] && [ ! -L "$STATE/.uuplugin_uuid" ] &&
    [ ! -L "$STATE/uu.tar.gz" ] || exit 65
if [ "$TARGET_ROOT" = / ]; then
    "$INIT" stop || {
        echo "MIPS_V2_UNINSTALL_DENIED: ownership or firewall cleanup incomplete" >&2
        exit 8
    }
    "$INIT" disable || {
        echo "MIPS_V2_UNINSTALL_DENIED: failed to disable service" >&2
        exit 8
    }
fi
# Remove only known managed application files. Never delete opaque device ID.
rm -f "$INIT" "$BACKUP" || exit 6
rm -rf "$OLD" "$NEW" || exit 6
if [ -f "$STATE/uu.tar.gz" ]; then
    rm -f "$STATE/uu.tar.gz" || exit 6
fi
[ -f "$STATE/.uuplugin_uuid" ] && echo "MIPS_V2_IDENTITY_PRESERVED"
echo "MIPS_V2_UNINSTALL_OK"
