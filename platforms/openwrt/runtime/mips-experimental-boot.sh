#!/bin/sh
# Lenovo Y1 opt-in experimental bootstrap, executed by procd.
# Only this small shell code is persisted; signed official binaries live in RAM.
set -u
APP_DIR=/usr/lib/uu-mips-wol-helper
STAGE_DIR=/tmp/uu-wol-helper-mips-persist
# Only isolated host fixtures can choose another app/staging directory.
# The real procd service always uses these fixed managed paths.
if [ "${UU_TEST_MODE:-0}" = 1 ]; then
    APP_DIR="${UU_MIPS_APP_DIR:-$APP_DIR}"
    STAGE_DIR="${UU_MIPS_STAGE_DIR:-$STAGE_DIR}"
fi
[ -f "$APP_DIR/install.meta" ] || exit 66
grep -qx 'managed_by=uu-remote-wol-router-helper-mips-beta' "$APP_DIR/install.meta" || exit 66
. "$APP_DIR/lib/channel.sh"
[ "$(uu_openwrt_detect_arch 2>/dev/null || true)" = mipsel_24kc ] || exit 67

# A real boot may bring up the campus network after the service starts.
# Never run a stale executable after network download/verification fails.
attempt=0
while [ "$attempt" -lt 20 ]; do
    if UU_STAGE_DIR="$STAGE_DIR" sh "$APP_DIR/scripts/stage-package.sh" openwrt-mipsel; then
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
# Stage gets validated afresh on every boot; never run unverified binaries.
cd "$STAGE_DIR/files" || exit 71
exec ./uuplugin ./uu.conf
