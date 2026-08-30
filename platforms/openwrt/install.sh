#!/bin/sh

set -u

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/../.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/lib/checksum.sh"
. "$ROOT_DIR/lib/archive.sh"
. "$ROOT_DIR/lib/evidence.sh"
. "$ROOT_DIR/lib/channel.sh"
. "$ROOT_DIR/platforms/openwrt/persist-common.sh"

TARGET_ROOT="${UU_TARGET_ROOT:-/}"
STAGE_DIR="${UU_STAGE_DIR:-/tmp/uu-wol-helper-stage}"
CONFIRM="${UU_PERSIST_INSTALL_CONFIRM:-}"
TEST_MODE="${UU_TEST_MODE:-0}"

if [ "$CONFIRM" != "PERSIST_OPENWRT_UU" ]; then
    cat >&2 <<'EOF'
Persistent OpenWrt install is disabled by default.
It writes /usr/lib/uu-wol-helper and /etc/init.d/uu-wol-helper.
To run after reviewing the script, set:
  UU_PERSIST_INSTALL_CONFIRM=PERSIST_OPENWRT_UU
A matching stage-MD5-bound smoke-pass marker is also required.
EOF
    exit 64
fi

if ! ow_validate_target_root "$TARGET_ROOT"; then
    echo "Unsafe target root. Real installs must use /; tests may use /tmp/uu-wol-helper-root-* with UU_TEST_MODE=1." >&2
    exit 2
fi

case "$STAGE_DIR" in
    /tmp/uu-wol-helper-*) ;;
    *)
        echo "Unsafe stage directory. UU_STAGE_DIR must match /tmp/uu-wol-helper-*" >&2
        exit 2
        ;;
esac

if [ "$TARGET_ROOT" = "/" ] && [ "$(id -u 2>/dev/null || printf 1)" != "0" ]; then
    echo "Root is required for a persistent OpenWrt install." >&2
    exit 3
fi

for cmd in cp mv rm mkdir chmod date grep sed md5sum tar; do
    command -v "$cmd" >/dev/null 2>&1 || {
        printf 'Required command is missing: %s\n' "$cmd" >&2
        exit 3
    }
done

if ! UU_OPENWRT_RELEASE_FILE="${UU_OPENWRT_RELEASE_FILE:-/etc/openwrt_release}" \
     UU_ARCH_OVERRIDE="${UU_ARCH_OVERRIDE:-$(uname -m 2>/dev/null || printf unknown)}" \
     sh "$ROOT_DIR/platforms/openwrt/preflight.sh" >/dev/null; then
    echo "Generic OpenWrt preflight failed; persistent install aborted." >&2
    exit 3
fi

metadata="$STAGE_DIR/metadata"
package="$STAGE_DIR/uu.tar.gz"
[ -f "$metadata" ] || { echo "Stage metadata is missing." >&2; exit 4; }
[ -f "$package" ] || { echo "Staged official package is missing." >&2; exit 4; }

stage_channel=$(sed -n 's/^channel=//p' "$metadata" | head -n 1)
stage_version=$(sed -n 's/^version=//p' "$metadata" | head -n 1)
stage_md5=$(sed -n 's/^md5=//p' "$metadata" | head -n 1 | tr 'A-F' 'a-f')
arch="${UU_ARCH_OVERRIDE:-$(uname -m 2>/dev/null || printf unknown)}"
expected_channel=$(uu_openwrt_channel_for_arch "$arch" 2>/dev/null || true)

[ -n "$expected_channel" ] || { echo "No confirmed official OpenWrt channel for this architecture." >&2; exit 4; }
[ "$stage_channel" = "$expected_channel" ] || {
    printf 'Staged channel mismatch: expected=%s actual=%s\n' "$expected_channel" "$stage_channel" >&2
    exit 4
}

uu_verify_md5 "$package" "$stage_md5" || {
    echo "Staged package no longer matches the verified MD5." >&2
    exit 4
}
uu_validate_uu_package "$package" || {
    echo "Staged package structure is no longer valid." >&2
    exit 4
}
uu_check_smoke_pass "$STAGE_DIR" openwrt "$stage_md5" || {
    echo "A matching OpenWrt smoke-pass marker is required before persistent install." >&2
    exit 5
}

for required in uuplugin xuplugin-guardian uu.conf xtables-nft-multi; do
    [ -f "$STAGE_DIR/files/$required" ] || {
        printf 'Staged file missing: %s\n' "$required" >&2
        exit 4
    }
done

if [ "$TARGET_ROOT" = "/" ] && ow_runtime_active; then
    echo "An existing UU runtime is active. Stop it explicitly before persistent install." >&2
    exit 65
fi

install_dir=$(ow_install_dir "$TARGET_ROOT")
init_path=$(ow_init_path "$TARGET_ROOT")
state_dir=$(ow_state_dir "$TARGET_ROOT")
backup_root="$state_dir/backups"

stamp=$(date +%Y%m%d-%H%M%S 2>/dev/null || printf unknown)
backup_dir="$backup_root/$stamp-$$"
mkdir -p "$backup_dir" || exit 6

had_install=no
had_init=no
previous_enabled=no

if [ -d "$install_dir" ]; then
    had_install=yes
    mkdir -p "$backup_dir/install" || exit 6
    cp -pR "$install_dir/." "$backup_dir/install/" || exit 6
fi

if [ -f "$init_path" ]; then
    had_init=yes
    cp -p "$init_path" "$backup_dir/init-script" || exit 6
fi

if ow_service_was_enabled "$TARGET_ROOT"; then
    previous_enabled=yes
fi

{
    printf 'had_install=%s\n' "$had_install"
    printf 'had_init=%s\n' "$had_init"
    printf 'previous_enabled=%s\n' "$previous_enabled"
} > "$backup_dir/manifest"

mkdir -p "$state_dir" || exit 6
printf '%s\n' "$backup_dir" > "$state_dir/last-backup"

new_dir="${install_dir}.new.$$"
rm -rf "$new_dir"
mkdir -p "$new_dir" || exit 6

for file in uuplugin xuplugin-guardian uu.conf xtables-nft-multi; do
    cp -p "$STAGE_DIR/files/$file" "$new_dir/$file" || exit 6
done
cp -p "$ROOT_DIR/platforms/openwrt/runtime/run.sh" "$new_dir/run.sh" || exit 6

chmod 0755 "$new_dir/uuplugin" "$new_dir/xuplugin-guardian" "$new_dir/xtables-nft-multi" "$new_dir/run.sh" || exit 6
chmod 0644 "$new_dir/uu.conf" || exit 6

{
    printf 'managed_by=uu-remote-wol-router-helper\n'
    printf 'platform=openwrt\n'
    printf 'channel=%s\n' "$stage_channel"
    printf 'version=%s\n' "$stage_version"
    printf 'md5=%s\n' "$stage_md5"
} > "$new_dir/install.meta"
chmod 0644 "$new_dir/install.meta" || exit 6

mkdir -p "$(dirname "$install_dir")" "$(dirname "$init_path")" || exit 6
rm -rf "$install_dir"
mv "$new_dir" "$install_dir" || exit 6
cp -p "$ROOT_DIR/platforms/openwrt/runtime/uu-wol-helper.init" "$init_path" || exit 6
chmod 0755 "$init_path" || exit 6

printf '%s\n' "Generic OpenWrt persistent install"
printf '%s\n' "=================================="
printf 'target_root: %s\n' "$TARGET_ROOT"
printf 'install_dir: %s\n' "$install_dir"
printf 'init_script: %s\n' "$init_path"
printf 'channel: %s\n' "$stage_channel"
printf 'version: %s\n' "$stage_version"
printf 'md5: %s\n' "$stage_md5"
printf 'backup_dir: %s\n' "$backup_dir"

rollback_failed_install() {
    reason="$1"
    printf 'install_failure: %s\n' "$reason" >&2
    if UU_TARGET_ROOT="$TARGET_ROOT" \
       UU_TEST_MODE="$TEST_MODE" \
       UU_ROLLBACK_CONFIRM=AUTO_ROLLBACK_AFTER_FAILED_INSTALL \
       sh "$ROOT_DIR/platforms/openwrt/rollback.sh" >/dev/null 2>&1; then
        echo "automatic_rollback: pass" >&2
    else
        echo "automatic_rollback: failed; manual recovery is required" >&2
    fi
}

if [ "$TARGET_ROOT" != "/" ] || [ "$TEST_MODE" = "1" ]; then
    printf '%s\n' "service_activation: skipped(test-root)"
    printf '%s\n' "INSTALL_FILES_READY"
    exit 0
fi

if ! "$init_path" enable; then
    rollback_failed_install "failed to enable the procd service"
    exit 7
fi

if ! "$init_path" start; then
    rollback_failed_install "failed to start the procd service"
    exit 7
fi

health_ok=no
elapsed=0
while [ "$elapsed" -lt 45 ]; do
    if UU_OPENWRT_PLUGIN_DIR="$install_dir" sh "$ROOT_DIR/platforms/openwrt/health.sh" >/dev/null 2>&1; then
        health_ok=yes
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

if [ "$health_ok" != "yes" ]; then
    rollback_failed_install "persistent service did not reach uuplugin + guardian + :16000 health within 45 seconds"
    exit 8
fi

printf 'service_activation: healthy_after_%ss\n' "$elapsed"
printf '%s\n' "INSTALL_OK"
