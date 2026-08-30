#!/bin/sh

set -u

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/../.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/platforms/xiaoqiang/persist-common.sh"

TARGET_ROOT="${UU_TARGET_ROOT:-/}"
CONFIRM="${UU_XQ_ROLLBACK_CONFIRM:-}"
TEST_MODE="${UU_TEST_MODE:-0}"
UCI_BIN="${UU_XQ_UCI_BIN:-uci}"
TEST_UCI="${UU_XQ_TEST_UCI:-0}"

case "$CONFIRM" in
    ROLLBACK_XIAOQIANG_UU|AUTO_ROLLBACK_AFTER_FAILED_INSTALL) ;;
    *)
        cat >&2 <<'EOF'
XiaoQiang rollback is disabled by default.
To restore the most recent pre-migration state, set:
  UU_XQ_ROLLBACK_CONFIRM=ROLLBACK_XIAOQIANG_UU
EOF
        exit 64
        ;;
esac

if ! xq_validate_target_root "$TARGET_ROOT"; then
    echo "Unsafe target root." >&2
    exit 2
fi

if [ "$TARGET_ROOT" = "/" ] && [ "$(id -u 2>/dev/null || printf 1)" != "0" ]; then
    echo "Root is required for XiaoQiang rollback." >&2
    exit 3
fi

plugin_dir=$(xq_plugin_dir "$TARGET_ROOT")
helper_dir=$(xq_helper_dir "$TARGET_ROOT")
state_dir=$(xq_state_dir "$TARGET_ROOT")
install_json=$(xq_install_json "$TARGET_ROOT")
last_backup="$state_dir/last-backup"
backup_root="$state_dir/backups"

[ -f "$last_backup" ] || { echo "No recorded XiaoQiang pre-migration backup is available." >&2; exit 4; }
backup_dir=$(sed -n '1p' "$last_backup")
case "$backup_dir" in
    "$backup_root"/*) ;;
    *) echo "Recorded backup path is outside the managed backup directory." >&2; exit 4 ;;
esac

manifest="$backup_dir/manifest"
[ -f "$manifest" ] || { echo "Backup manifest is missing." >&2; exit 4; }

had_helper=$(sed -n 's/^had_helper=//p' "$manifest" | head -n 1)
previous_runtime=$(sed -n 's/^previous_runtime=//p' "$manifest" | head -n 1)
firewall_exists=$(sed -n 's/^firewall_exists=//p' "$manifest" | head -n 1)
firewall_type=$(sed -n 's/^firewall_type=//p' "$manifest" | head -n 1)
firewall_path=$(sed -n 's/^firewall_path=//p' "$manifest" | head -n 1)
firewall_enabled=$(sed -n 's/^firewall_enabled=//p' "$manifest" | head -n 1)

case "$had_helper:$previous_runtime:$firewall_exists" in
    yes:yes:yes|yes:yes:no|yes:no:yes|yes:no:no|no:yes:yes|no:yes:no|no:no:yes|no:no:no) ;;
    *) echo "Backup manifest contains invalid values." >&2; exit 4 ;;
esac

[ -d "$backup_dir/plugin" ] || { echo "Plugin backup is missing." >&2; exit 5; }
[ -f "$backup_dir/installPlugin/2882303761518031252.json" ] || { echo "installPlugin JSON backup is missing." >&2; exit 5; }

if [ "$TARGET_ROOT" = "/" ] && [ "$TEST_MODE" != "1" ]; then
    if [ -x "$plugin_dir/xnetease-uu" ]; then
        "$plugin_dir/xnetease-uu" plugoff >/dev/null 2>&1 || true
    else
        killall uuplugin_monitor.sh 2>/dev/null || true
        killall uuplugin 2>/dev/null || true
        killall xuplugin-guardian 2>/dev/null || true
    fi
    sleep 2
fi

rm -rf "$plugin_dir"
mkdir -p "$plugin_dir" || exit 5
cp -pR "$backup_dir/plugin/." "$plugin_dir/" || exit 5

rm -rf "$helper_dir"
if [ "$had_helper" = "yes" ]; then
    [ -d "$backup_dir/helper" ] || { echo "Helper backup is missing." >&2; exit 5; }
    mkdir -p "$helper_dir" || exit 5
    cp -pR "$backup_dir/helper/." "$helper_dir/" || exit 5
fi

mkdir -p "$(dirname "$install_json")" || exit 5
cp -p "$backup_dir/installPlugin/2882303761518031252.json" "$install_json" || exit 5

if [ "$TARGET_ROOT" = "/" ] || { [ "$TEST_MODE" = "1" ] && [ "$TEST_UCI" = "1" ]; }; then
    "$UCI_BIN" -q delete firewall.uuplugin
    if [ "$firewall_exists" = "yes" ]; then
        "$UCI_BIN" set firewall.uuplugin=include || exit 6
        [ -n "$firewall_type" ] && "$UCI_BIN" set firewall.uuplugin.type="$firewall_type"
        [ -n "$firewall_path" ] && "$UCI_BIN" set firewall.uuplugin.path="$firewall_path"
        [ -n "$firewall_enabled" ] && "$UCI_BIN" set firewall.uuplugin.enabled="$firewall_enabled"
    fi
    "$UCI_BIN" commit firewall || exit 6
fi

if [ "$TARGET_ROOT" = "/" ] && [ "$TEST_MODE" != "1" ]; then
    if [ "$previous_runtime" = "yes" ] && [ -x "$plugin_dir/xnetease-uu" ]; then
        "$plugin_dir/xnetease-uu" plugon >/dev/null 2>&1 || true
    fi
fi

printf '%s\n' "$backup_dir" > "$state_dir/last-rollback"
rm -f "$last_backup"

printf '%s\n' "XiaoQiang rollback"
printf '%s\n' "=================="
printf 'restored_backup: %s\n' "$backup_dir"
printf 'restored_helper: %s\n' "$had_helper"
printf 'restored_firewall_section: %s\n' "$firewall_exists"
printf 'restored_previous_runtime: %s\n' "$previous_runtime"
printf '%s\n' "ROLLBACK_OK"
