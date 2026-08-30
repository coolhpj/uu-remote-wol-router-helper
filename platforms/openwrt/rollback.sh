#!/bin/sh

set -u

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/../.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/platforms/openwrt/persist-common.sh"

TARGET_ROOT="${UU_TARGET_ROOT:-/}"
CONFIRM="${UU_ROLLBACK_CONFIRM:-}"
TEST_MODE="${UU_TEST_MODE:-0}"

case "$CONFIRM" in
    ROLLBACK_OPENWRT_UU|AUTO_ROLLBACK_AFTER_FAILED_INSTALL) ;;
    *)
        cat >&2 <<'EOF'
Rollback is disabled by default.
To restore the most recent pre-install state, set:
  UU_ROLLBACK_CONFIRM=ROLLBACK_OPENWRT_UU
EOF
        exit 64
        ;;
esac

if ! ow_validate_target_root "$TARGET_ROOT"; then
    echo "Unsafe target root." >&2
    exit 2
fi

if [ "$TARGET_ROOT" = "/" ] && [ "$(id -u 2>/dev/null || printf 1)" != "0" ]; then
    echo "Root is required for rollback." >&2
    exit 3
fi

install_dir=$(ow_install_dir "$TARGET_ROOT")
init_path=$(ow_init_path "$TARGET_ROOT")
state_dir=$(ow_state_dir "$TARGET_ROOT")
last_backup="$state_dir/last-backup"
backup_root="$state_dir/backups"

[ -f "$last_backup" ] || {
    echo "No recorded pre-install backup is available." >&2
    exit 4
}

backup_dir=$(sed -n '1p' "$last_backup")
case "$backup_dir" in
    "$backup_root"/*) ;;
    *)
        echo "Recorded backup path is outside the managed backup directory." >&2
        exit 4
        ;;
esac

manifest="$backup_dir/manifest"
[ -f "$manifest" ] || { echo "Backup manifest is missing." >&2; exit 4; }

had_install=$(sed -n 's/^had_install=//p' "$manifest" | head -n 1)
had_init=$(sed -n 's/^had_init=//p' "$manifest" | head -n 1)
previous_enabled=$(sed -n 's/^previous_enabled=//p' "$manifest" | head -n 1)

case "$had_install:$had_init:$previous_enabled" in
    yes:yes:yes|yes:yes:no|yes:no:yes|yes:no:no|no:yes:yes|no:yes:no|no:no:yes|no:no:no) ;;
    *) echo "Backup manifest contains invalid values." >&2; exit 4 ;;
esac

if [ "$TARGET_ROOT" = "/" ] && [ "$TEST_MODE" != "1" ] && [ -x "$init_path" ]; then
    "$init_path" stop >/dev/null 2>&1 || true
    "$init_path" disable >/dev/null 2>&1 || true
fi

rm -rf "$install_dir"
rm -f "$init_path"

if [ "$had_install" = "yes" ]; then
    [ -d "$backup_dir/install" ] || { echo "Install backup is missing." >&2; exit 5; }
    mkdir -p "$install_dir" || exit 5
    cp -pR "$backup_dir/install/." "$install_dir/" || exit 5
fi

if [ "$had_init" = "yes" ]; then
    [ -f "$backup_dir/init-script" ] || { echo "Init-script backup is missing." >&2; exit 5; }
    mkdir -p "$(dirname "$init_path")" || exit 5
    cp -p "$backup_dir/init-script" "$init_path" || exit 5
    chmod 0755 "$init_path" || exit 5
fi

if [ "$TARGET_ROOT" = "/" ] && [ "$TEST_MODE" != "1" ] && [ "$had_init" = "yes" ] && [ "$previous_enabled" = "yes" ]; then
    "$init_path" enable >/dev/null 2>&1 || true
    "$init_path" start >/dev/null 2>&1 || true
fi

printf '%s\n' "$backup_dir" > "$state_dir/last-rollback"
rm -f "$last_backup"

printf '%s\n' "Generic OpenWrt rollback"
printf '%s\n' "========================"
printf 'target_root: %s\n' "$TARGET_ROOT"
printf 'restored_backup: %s\n' "$backup_dir"
printf 'restored_install: %s\n' "$had_install"
printf 'restored_init: %s\n' "$had_init"
printf 'restored_enabled_state: %s\n' "$previous_enabled"
printf '%s\n' "ROLLBACK_OK"
