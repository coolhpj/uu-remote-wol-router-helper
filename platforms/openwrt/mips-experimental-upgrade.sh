#!/bin/sh
# Lenovo Y1 beta v1 -> identity-safe v2 on-next-boot upgrade.
# No plugin/network/firewall restart: active v1 keeps running until normal reboot.
set -u
ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/../.." && pwd) || exit 1
. "$ROOT_DIR/lib/channel.sh"
. "$ROOT_DIR/platforms/openwrt/persist-common.sh"
. "$ROOT_DIR/platforms/openwrt/runtime/mips-uuid-state.sh"
[ "${UU_MIPS_BETA_UPGRADE_CONFIRM:-}" = I_ACCEPT_Y1_IDENTITY_SAFE_UPGRADE ] || {
    echo "MIPS_BETA_UPGRADE_DENIED: explicit opt-in required" >&2; exit 64;
}
TARGET_ROOT="${UU_TARGET_ROOT:-/}"
ow_validate_target_root "$TARGET_ROOT" || exit 2
if [ "$TARGET_ROOT" = / ]; then
    [ "$(id -u 2>/dev/null)" = 0 ] || exit 3
    [ "$(uu_openwrt_detect_arch 2>/dev/null || true)" = mipsel_24kc ] || exit 67
    model=$(cat /tmp/sysinfo/model 2>/dev/null || true)
    release=$(sed -n 's/^DISTRIB_TARGET=//p' /etc/openwrt_release | tr -d "'\"")
    case "$model" in *"Lenovo Y1"*|*"Newifi mini R6830"*) ;; *) exit 67 ;; esac
    [ "$release" = ramips/mt7620 ] || exit 67
    OLD=/usr/lib/uu-mips-wol-helper
    NEXT=/usr/lib/uu-mips-wol-helper-v2
    INIT=/etc/init.d/uu-mips-wol-helper
else
    [ "${UU_TEST_MODE:-0}" = 1 ] || exit 2
    OLD="$TARGET_ROOT/usr/lib/uu-mips-wol-helper"
    NEXT="$TARGET_ROOT/usr/lib/uu-mips-wol-helper-v2"
    INIT="$TARGET_ROOT/etc/init.d/uu-mips-wol-helper"
fi
BACKUP="$INIT.v1-backup"
[ -d "$OLD" ] && [ ! -L "$OLD" ] && [ -f "$OLD/install.meta" ] &&
    grep -qx 'managed_by=uu-remote-wol-router-helper-mips-beta' "$OLD/install.meta" ||
    { echo "MIPS_BETA_UPGRADE_DENIED: no owned v1 app" >&2; exit 65; }
[ -f "$INIT" ] && [ ! -L "$INIT" ] &&
    grep -qx '# managed_by=uu-remote-wol-router-helper-mips-beta' "$INIT" ||
    { echo "MIPS_BETA_UPGRADE_DENIED: unowned service" >&2; exit 65; }
[ ! -e "$NEXT" ] && [ ! -L "$NEXT" ] && [ ! -e "$BACKUP" ] && [ ! -L "$BACKUP" ] ||
    { echo "MIPS_BETA_UPGRADE_DENIED: upgrade or backup already exists" >&2; exit 65; }

# Rescue the currently bound identity BEFORE any on-flash service switch.
# A missing current and saved identity must not be silently replaced.
uu_uuid_paths
if [ -e "$UU_UUID_STORED" ] || [ -L "$UU_UUID_STORED" ]; then
    uu_uuid_valid "$UU_UUID_STORED" || {
        echo "MIPS_BETA_UPGRADE_DENIED: saved identity invalid" >&2; exit 72;
    }
    if [ -e "$UU_UUID_RUNTIME" ] || [ -L "$UU_UUID_RUNTIME" ]; then
        uu_uuid_valid "$UU_UUID_RUNTIME" && cmp -s "$UU_UUID_RUNTIME" "$UU_UUID_STORED" ||
            { echo "MIPS_BETA_UPGRADE_DENIED: identity conflict" >&2; exit 72; }
    fi
else
    uu_uuid_backup_once || {
        echo "MIPS_BETA_UPGRADE_DENIED: live UUID missing; keep existing service" >&2; exit 72;
    }
fi

if [ "$TARGET_ROOT" = / ]; then
    flash_kb=$(df -Pk /overlay | awk 'NR==2 {print $4}')
    case "$flash_kb" in ''|*[!0-9]*) exit 5 ;; esac
    [ "$flash_kb" -ge 4096 ] || {
        echo "MIPS_BETA_UPGRADE_DENIED: insufficient flash for backup" >&2; exit 5;
    }
fi

TEMP="$NEXT.new.$$"
INIT_TEMP="$INIT.new.$$"
BACKUP_TEMP="$BACKUP.new.$$"
[ ! -e "$TEMP" ] && [ ! -L "$TEMP" ] && [ ! -e "$INIT_TEMP" ] && [ ! -L "$INIT_TEMP" ] && [ ! -e "$BACKUP_TEMP" ] || exit 65
trap 'rm -rf "$TEMP"; rm -f "$INIT_TEMP" "$BACKUP_TEMP"' EXIT HUP INT TERM
mkdir -p "$TEMP/lib" "$TEMP/scripts" || exit 6
for file in channel.sh checksum.sh archive.sh elf.sh netease-api.sh download.sh mips-package-cache.sh; do
    cp "$ROOT_DIR/lib/$file" "$TEMP/lib/$file" || exit 6
done
cp "$ROOT_DIR/scripts/stage-package.sh" "$TEMP/scripts/stage-package.sh" || exit 6
cp "$ROOT_DIR/platforms/openwrt/runtime/mips-experimental-boot.sh" "$TEMP/boot.sh" || exit 6
cp "$ROOT_DIR/platforms/openwrt/runtime/mips-experimental-stop.sh" "$TEMP/stop.sh" || exit 6
cp "$ROOT_DIR/platforms/openwrt/runtime/mips-uuid-state.sh" "$TEMP/uuid-state.sh" || exit 6
cp "$ROOT_DIR/platforms/openwrt/runtime/mips-uuid-watch.sh" "$TEMP/uuid-watch.sh" || exit 6
cp "$OLD/install.meta" "$TEMP/install.meta" || exit 6
chmod 755 "$TEMP/boot.sh" "$TEMP/stop.sh" "$TEMP/uuid-watch.sh" "$TEMP/scripts/stage-package.sh" || exit 6
# Switch is atomic at the init FILE, not a partially replaced app directory.
sed 's|/usr/lib/uu-mips-wol-helper/|/usr/lib/uu-mips-wol-helper-v2/|g' \
    "$ROOT_DIR/platforms/openwrt/runtime/mips-experimental.init" > "$INIT_TEMP" || exit 6
grep -qx 'PROG=/usr/lib/uu-mips-wol-helper-v2/boot.sh' "$INIT_TEMP" || exit 6
grep -qx '# managed_by=uu-remote-wol-router-helper-mips-beta' "$INIT_TEMP" || exit 6
chmod 755 "$INIT_TEMP" || exit 6
mv "$TEMP" "$NEXT" || exit 6
cp "$INIT" "$BACKUP_TEMP" || exit 6
chmod 755 "$BACKUP_TEMP" || exit 6
mv "$BACKUP_TEMP" "$BACKUP" || exit 6
# Persist the complete v2 app and rollback copy before activating new init.
sync
if ! mv -f "$INIT_TEMP" "$INIT"; then
    echo "MIPS_BETA_UPGRADE_FAILED: old init still active; backup retained" >&2
    exit 6
fi
sync
echo "MIPS_BETA_V2_READY_NEXT_BOOT: v1 app and init backup retained"
echo "MIPS_BETA_V2_WOL_NOT_YET_VERIFIED"
