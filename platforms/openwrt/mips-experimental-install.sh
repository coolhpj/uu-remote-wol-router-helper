#!/bin/sh
# Opt-in Lenovo Y1 / MT7620 MIPS persistent bootstrap experiment.
# No proprietary binary is copied into flash. Generic installer stays blocked.
set -u
ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/../.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/lib/channel.sh"
. "$ROOT_DIR/lib/checksum.sh"
. "$ROOT_DIR/lib/archive.sh"
. "$ROOT_DIR/lib/elf.sh"
. "$ROOT_DIR/platforms/openwrt/persist-common.sh"
TARGET_ROOT="${UU_TARGET_ROOT:-/}"
STAGE_DIR="${UU_STAGE_DIR:-/tmp/uu-wol-helper-stage}"
CONFIRM="${UU_MIPS_BETA_INSTALL_CONFIRM:-}"
[ "$CONFIRM" = "I_ACCEPT_LENOVO_Y1_EXPERIMENTAL_PERSISTENCE" ] || {
    echo "MIPS beta install disabled: explicit Lenovo Y1 opt-in required" >&2
    exit 64
}
ow_validate_target_root "$TARGET_ROOT" || exit 2
case "$STAGE_DIR" in /tmp/uu-wol-helper-*) ;; *) exit 2 ;; esac
[ "$TARGET_ROOT" != / ] || [ "$(id -u 2>/dev/null || echo 1)" = 0 ] || exit 3
[ ! -e "$STAGE_DIR/mips-smoke.lock" ] || {
    echo "An incomplete MIPS temporary test must be recovered first" >&2
    exit 65
}
arch=$(uu_openwrt_detect_arch 2>/dev/null || true)
if [ "$arch" != mipsel_24kc ]; then
    echo "Only little-endian MIPS 24K is eligible for this beta" >&2
    exit 67
fi

# Do not broaden beta to a CPU architecture. Require this exact device.
if [ "$TARGET_ROOT" = / ]; then
    model=$(cat /tmp/sysinfo/model 2>/dev/null || true)
    release=$(sed -n 's/^DISTRIB_TARGET=//p' /etc/openwrt_release | tr -d "'\"" )
else
    model="${UU_TEST_MODEL:-}"
    release=ramips/mt7620
fi
case "$model" in
    *"Lenovo Y1"*|*"Newifi mini R6830"*) ;;
    *) echo "Not an independently identified Lenovo Y1" >&2; exit 67 ;;
esac
[ "$release" = ramips/mt7620 ] || {
    echo "Wrong OpenWrt target, expected ramips/mt7620" >&2
    exit 67
}

# Stage proof for *this* verified official package: no trust in raw files.
md5=$(sed -n 's/^md5=//p' "$STAGE_DIR/metadata" 2>/dev/null | head -n 1)
channel=$(sed -n 's/^channel=//p' "$STAGE_DIR/metadata" 2>/dev/null | head -n 1)
[ "$channel" = openwrt-mipsel ] && uu_verify_md5 "$STAGE_DIR/uu.tar.gz" "$md5" &&
    uu_validate_uu_package "$STAGE_DIR/uu.tar.gz" &&
    uu_check_stage_mipsel_elf "$STAGE_DIR" || {
        echo "MIPS stage is not a verified official package" >&2
        exit 4
    }

APP="$TARGET_ROOT/usr/lib/uu-mips-wol-helper"
INIT="$TARGET_ROOT/etc/init.d/uu-mips-wol-helper"
# On a real host root=/ must not create //.
[ "$TARGET_ROOT" = / ] && {
    APP=/usr/lib/uu-mips-wol-helper
    INIT=/etc/init.d/uu-mips-wol-helper
}
[ ! -e "$APP" ] && [ ! -L "$APP" ] && [ ! -e "$INIT" ] && [ ! -L "$INIT" ] || {
    echo "Refusing to overwrite any existing installation" >&2
    exit 65
}
if [ "$TARGET_ROOT" = / ]; then
    command -v procd_open_instance >/dev/null 2>&1 || : # rc.common provides procd functions
    [ -f /etc/rc.common ] && [ -x /sbin/procd ] || {
        echo "procd service manager unavailable" >&2
        exit 5
    }
    [ -d /overlay ] || exit 5
    free_kb=$(df -Pk /overlay | awk 'NR==2 {print $4}')
    case "$free_kb" in ''|*[!0-9]*) exit 5 ;; esac
    [ "$free_kb" -ge 2048 ] || {
        echo "Less than 2 MiB free flash; beta bootstrap install refused" >&2
        exit 5
    }
    if ps 2>/dev/null | grep -E '[u]uplugin|[x]uplugin-guardian|[u]uplugin_monitor' >/dev/null 2>&1; then
        echo "Existing UU runtime detected, not replacing it" >&2
        exit 65
    fi
    tables=$(nft list tables 2>/dev/null) || exit 5
    ! printf '%s\n' "$tables" | grep 'XU_' >/dev/null 2>&1 || exit 65
fi

temp="${APP}.new.$$"
mkdir -p "$temp/lib" "$temp/scripts" "$(dirname "$INIT")" || exit 6
trap 'rm -rf "$temp"' EXIT HUP INT TERM
for file in channel.sh checksum.sh archive.sh elf.sh netease-api.sh download.sh mips-package-cache.sh; do
    cp "$ROOT_DIR/lib/$file" "$temp/lib/$file" || exit 6
done
cp "$ROOT_DIR/scripts/stage-package.sh" "$temp/scripts/stage-package.sh" || exit 6
cp "$ROOT_DIR/platforms/openwrt/runtime/mips-experimental-boot.sh" "$temp/boot.sh" || exit 6
cp "$ROOT_DIR/platforms/openwrt/runtime/mips-experimental-stop.sh" "$temp/stop.sh" || exit 6
cp "$ROOT_DIR/platforms/openwrt/runtime/mips-uuid-state.sh" "$temp/uuid-state.sh" || exit 6
cp "$ROOT_DIR/platforms/openwrt/runtime/mips-uuid-watch.sh" "$temp/uuid-watch.sh" || exit 6
chmod 0755 "$temp/boot.sh" "$temp/stop.sh" "$temp/scripts/stage-package.sh" || exit 6
printf 'managed_by=uu-remote-wol-router-helper-mips-beta\nmodel=Lenovo Y1\nstage_md5=%s\n' "$md5" > "$temp/install.meta" || exit 6
chmod 0644 "$temp/install.meta" || exit 6
mv "$temp" "$APP" || exit 6
if ! cp "$ROOT_DIR/platforms/openwrt/runtime/mips-experimental.init" "$INIT" ||
   ! chmod 0755 "$INIT"; then
    rm -f "$INIT"
    rm -rf "$APP"
    exit 6
fi
trap - EXIT HUP INT TERM
if [ "$TARGET_ROOT" != / ]; then
    echo "MIPS_BETA_INSTALL_FILES_READY"
    exit 0
fi
# An installation never reuses an unvalidated smoke-pass marker.
# The new service redownloads and revalidates the official MIPS package on boot.
if ! "$INIT" enable || ! "$INIT" start; then
    "$INIT" disable >/dev/null 2>&1 || true
    echo "MIPS_BETA_START_FAILED: stop and uninstall explicitly; inspect status" >&2
    exit 7
fi
echo "MIPS_BETA_INSTALL_OK: verify real reboot, cloud and mobile-data WOL"
