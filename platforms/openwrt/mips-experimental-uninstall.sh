#!/bin/sh
# Uninstall only the dedicated Lenovo Y1 beta service, not any other UU code.
set -u
ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/../.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/platforms/openwrt/persist-common.sh"
TARGET_ROOT="${UU_TARGET_ROOT:-/}"
[ "${UU_MIPS_BETA_UNINSTALL_CONFIRM:-}" = REMOVE_LENOVO_Y1_BETA_SERVICE ] || {
    echo "MIPS beta uninstall requires explicit confirmation" >&2
    exit 64
}
ow_validate_target_root "$TARGET_ROOT" || exit 2
if [ "$TARGET_ROOT" = / ]; then
    APP=/usr/lib/uu-mips-wol-helper
    INIT=/etc/init.d/uu-mips-wol-helper
    [ "$(id -u 2>/dev/null || echo 1)" = 0 ] || exit 3
else
    APP="$TARGET_ROOT/usr/lib/uu-mips-wol-helper"
    INIT="$TARGET_ROOT/etc/init.d/uu-mips-wol-helper"
fi
[ -d "$APP" ] && [ ! -L "$APP" ] && [ -f "$APP/install.meta" ] &&
    grep -qx 'managed_by=uu-remote-wol-router-helper-mips-beta' "$APP/install.meta" ||
    { echo "No managed beta app found; refusing to remove unrelated files" >&2; exit 4; }
[ -f "$INIT" ] && [ ! -L "$INIT" ] &&
    grep -qx '# managed_by=uu-remote-wol-router-helper-mips-beta' "$INIT" ||
    { echo "No managed beta init found; refusing to remove unrelated files" >&2; exit 4; }
if [ "$TARGET_ROOT" = / ]; then
    # Stop must complete first. Never uninstall on uncertain cleanup.
    "$INIT" stop || {
        echo "MIPS_BETA_UNINSTALL_BLOCKED: process/firewall cleanup incomplete" >&2
        exit 8
    }
    "$INIT" disable || {
        echo "MIPS_BETA_UNINSTALL_BLOCKED: service disable failed" >&2
        exit 8
    }
fi
rm -f "$INIT" || exit 6
rm -rf "$APP" || exit 6
echo "MIPS_BETA_UNINSTALL_OK"
