#!/bin/sh
# Lenovo Y1 opt-in experimental bootstrap, executed by procd.
# Only this small shell code is persisted; signed official binaries live in RAM.
set -u
APP_DIR=/usr/lib/uu-mips-wol-helper
STAGE_DIR=/tmp/uu-wol-helper-mips-persist
if [ "${UU_TEST_MODE:-0}" = 1 ]; then
    APP_DIR="${UU_MIPS_APP_DIR:-$APP_DIR}"
    STAGE_DIR="${UU_MIPS_STAGE_DIR:-$STAGE_DIR}"
else
    # Both paths are fixed, owned installations; never accept a runtime override.
    case "$0" in
        /usr/lib/uu-mips-wol-helper/boot.sh) ;;
        /usr/lib/uu-mips-wol-helper-v2/boot.sh) APP_DIR=/usr/lib/uu-mips-wol-helper-v2 ;;
        *) echo "MIPS_BOOT_UNOWNED_PATH" >&2; exit 66 ;;
    esac
fi
[ -f "$APP_DIR/install.meta" ] || exit 66
grep -qx 'managed_by=uu-remote-wol-router-helper-mips-beta' "$APP_DIR/install.meta" || exit 66
. "$APP_DIR/lib/channel.sh"
[ "$(uu_openwrt_detect_arch 2>/dev/null || true)" = mipsel_24kc ] || exit 67
. "$APP_DIR/uuid-state.sh" || exit 72
uu_uuid_preserve_before_stage || {
    echo "MIPS_UUID_UNSAVED: refusing to re-stage an existing identity" >&2
    exit 72
}

# A real boot may bring up the campus network after the service starts.
# Never run a stale executable after network download/verification fails.
attempt=0
while [ "$attempt" -lt 20 ]; do
    if UU_STAGE_DIR="$STAGE_DIR" UU_MIPS_ENABLE_CACHE=1 sh "$APP_DIR/scripts/stage-package.sh" openwrt-mipsel; then
        break
    fi
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 20 ]; then
        echo "MIPS official package could not be verified; plugin not started" >&2
        exit 69
    fi
    sleep 15
done

[ -f "$STAGE_DIR/metadata" ] || exit 70
grep -qx 'channel=openwrt-mipsel' "$STAGE_DIR/metadata" || exit 70
. "$APP_DIR/lib/elf.sh"
uu_check_stage_mipsel_elf "$STAGE_DIR" || exit 70
# Restore the original device identity after staging, before plugin startup.
# A malformed saved identity blocks startup rather than registering a new device.
uu_uuid_restore || exit 72
uu_uuid_initial_capacity_guard || {
    echo "MIPS_UUID_STORAGE_UNAVAILABLE: first binding cannot be safely persisted" >&2
    exit 73
}
# Stage gets validated afresh on every boot; never run unverified binaries.
cd "$STAGE_DIR/files" || exit 71
exec ./uuplugin ./uu.conf
