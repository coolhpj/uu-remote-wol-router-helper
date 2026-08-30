#!/bin/sh
set -u

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/lib/evidence.sh"

failures=0

ok() { printf 'ok - %s\n' "$1"; }
not_ok() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }

base="/tmp/uu-wol-helper-persist-test-$$"
stage="/tmp/uu-wol-helper-persist-stage-$$"
root1="/tmp/uu-wol-helper-root-$$-a"
root2="/tmp/uu-wol-helper-root-$$-b"

cleanup() {
    rm -rf "$base" "$stage" "$root1" "$root2"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$base/pkg" "$stage/files" "$root1/etc/init.d" "$root1/usr/lib/uu-wol-helper" "$root2/etc/init.d"

for file in uuplugin xuplugin-guardian xtables-nft-multi; do
    printf '#!/bin/sh\nexit 0\n' > "$base/pkg/$file"
    chmod 0755 "$base/pkg/$file"
done
printf 'log_level=info\nversion=v-test\n' > "$base/pkg/uu.conf"

(
    cd "$base/pkg" || exit 1
    tar -czf "$stage/uu.tar.gz" uuplugin xuplugin-guardian uu.conf xtables-nft-multi
) || exit 1
cp -p "$base/pkg/"* "$stage/files/"
md5=$(md5sum "$stage/uu.tar.gz" | awk '{print $1}')
printf 'channel=openwrt-x86_64\nversion=v-test\nmd5=%s\n' "$md5" > "$stage/metadata"

printf "DISTRIB_DESCRIPTION='Test OpenWrt'\nDISTRIB_TARGET='x86/64'\n" > "$root1/etc/openwrt_release"
printf "DISTRIB_DESCRIPTION='Test OpenWrt'\nDISTRIB_TARGET='x86/64'\n" > "$root2/etc/openwrt_release"

out=$(UU_TARGET_ROOT="$root1" UU_TEST_MODE=1 UU_STAGE_DIR="$stage" UU_OPENWRT_RELEASE_FILE="$root1/etc/openwrt_release" UU_ARCH_OVERRIDE=x86_64 sh "$ROOT_DIR/platforms/openwrt/install.sh" 2>&1)
rc=$?
if [ "$rc" -eq 64 ] && printf '%s' "$out" | grep 'disabled by default' >/dev/null 2>&1; then
    ok "persistent install is disabled by default"
else
    not_ok "persistent install is disabled by default"
fi

out=$(UU_TARGET_ROOT="$root1" UU_TEST_MODE=1 UU_STAGE_DIR="$stage" UU_OPENWRT_RELEASE_FILE="$root1/etc/openwrt_release" UU_ARCH_OVERRIDE=x86_64 UU_PERSIST_INSTALL_CONFIRM=PERSIST_OPENWRT_UU sh "$ROOT_DIR/platforms/openwrt/install.sh" 2>&1)
rc=$?
if [ "$rc" -eq 5 ] && printf '%s' "$out" | grep 'smoke-pass' >/dev/null 2>&1; then
    ok "persistent install requires smoke-pass evidence"
else
    not_ok "persistent install requires smoke-pass evidence"
fi

uu_write_smoke_pass "$stage" openwrt "$md5" || exit 1

printf 'legacy-install\n' > "$root1/usr/lib/uu-wol-helper/legacy.txt"
printf '#!/bin/sh\necho legacy-init\n' > "$root1/etc/init.d/uu-wol-helper"
chmod 0755 "$root1/etc/init.d/uu-wol-helper"

out=$(UU_TARGET_ROOT="$root1" UU_TEST_MODE=1 UU_STAGE_DIR="$stage" UU_OPENWRT_RELEASE_FILE="$root1/etc/openwrt_release" UU_ARCH_OVERRIDE=x86_64 UU_PERSIST_INSTALL_CONFIRM=PERSIST_OPENWRT_UU sh "$ROOT_DIR/platforms/openwrt/install.sh" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep 'INSTALL_FILES_READY' >/dev/null 2>&1; then
    ok "persistent install writes managed files under test root"
else
    not_ok "persistent install writes managed files under test root"
fi

if [ -x "$root1/usr/lib/uu-wol-helper/uuplugin" ] && \
   [ -x "$root1/usr/lib/uu-wol-helper/run.sh" ] && \
   [ -f "$root1/usr/lib/uu-wol-helper/install.meta" ] && \
   [ -x "$root1/etc/init.d/uu-wol-helper" ]; then
    ok "persistent install creates runtime and procd files"
else
    not_ok "persistent install creates runtime and procd files"
fi

if grep '^managed_by=uu-remote-wol-router-helper$' "$root1/usr/lib/uu-wol-helper/install.meta" >/dev/null 2>&1 && \
   grep '^# managed_by=uu-remote-wol-router-helper$' "$root1/etc/init.d/uu-wol-helper" >/dev/null 2>&1; then
    ok "managed ownership markers are written"
else
    not_ok "managed ownership markers are written"
fi

out=$(UU_TARGET_ROOT="$root1" UU_TEST_MODE=1 UU_ROLLBACK_CONFIRM=ROLLBACK_OPENWRT_UU sh "$ROOT_DIR/platforms/openwrt/rollback.sh" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep 'ROLLBACK_OK' >/dev/null 2>&1; then
    ok "rollback restores the recorded pre-install state"
else
    not_ok "rollback restores the recorded pre-install state"
fi

if [ -f "$root1/usr/lib/uu-wol-helper/legacy.txt" ] && grep 'legacy-init' "$root1/etc/init.d/uu-wol-helper" >/dev/null 2>&1; then
    ok "rollback restores previous install and init script"
else
    not_ok "rollback restores previous install and init script"
fi

out=$(UU_TARGET_ROOT="$root1" UU_TEST_MODE=1 UU_UNINSTALL_CONFIRM=UNINSTALL_OPENWRT_UU sh "$ROOT_DIR/platforms/openwrt/uninstall.sh" 2>&1)
rc=$?
if [ "$rc" -eq 4 ]; then
    ok "uninstall refuses unrelated restored files"
else
    not_ok "uninstall refuses unrelated restored files"
fi

out=$(UU_TARGET_ROOT="$root2" UU_TEST_MODE=1 UU_STAGE_DIR="$stage" UU_OPENWRT_RELEASE_FILE="$root2/etc/openwrt_release" UU_ARCH_OVERRIDE=x86_64 UU_PERSIST_INSTALL_CONFIRM=PERSIST_OPENWRT_UU sh "$ROOT_DIR/platforms/openwrt/install.sh" 2>&1)
rc=$?
if [ "$rc" -eq 0 ]; then
    ok "fresh managed install succeeds under second test root"
else
    not_ok "fresh managed install succeeds under second test root"
fi

out=$(UU_TARGET_ROOT="$root2" UU_TEST_MODE=1 UU_UNINSTALL_CONFIRM=UNINSTALL_OPENWRT_UU sh "$ROOT_DIR/platforms/openwrt/uninstall.sh" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep 'UNINSTALL_OK' >/dev/null 2>&1 && \
   [ ! -e "$root2/usr/lib/uu-wol-helper" ] && [ ! -e "$root2/etc/init.d/uu-wol-helper" ]; then
    ok "uninstall removes only managed runtime and init files"
else
    not_ok "uninstall removes only managed runtime and init files"
fi

if [ "$failures" -ne 0 ]; then
    printf '%s test(s) failed\n' "$failures" >&2
    exit 1
fi

printf 'all Generic OpenWrt persistence tests passed\n'
