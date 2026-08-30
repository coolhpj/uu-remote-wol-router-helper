#!/bin/sh

set -u

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/../.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/platforms/openwrt/persist-common.sh"

TARGET_ROOT="${UU_TARGET_ROOT:-/}"
CONFIRM="${UU_UNINSTALL_CONFIRM:-}"
TEST_MODE="${UU_TEST_MODE:-0}"

if [ "$CONFIRM" != "UNINSTALL_OPENWRT_UU" ]; then
    cat >&2 <<'EOF'
Uninstall is disabled by default.
To remove only files managed by this project, set:
  UU_UNINSTALL_CONFIRM=UNINSTALL_OPENWRT_UU
Backups under /etc/uu-wol-helper are preserved.
EOF
    exit 64
fi

if ! ow_validate_target_root "$TARGET_ROOT"; then
    echo "Unsafe target root." >&2
    exit 2
fi

if [ "$TARGET_ROOT" = "/" ] && [ "$(id -u 2>/dev/null || printf 1)" != "0" ]; then
    echo "Root is required for uninstall." >&2
    exit 3
fi

install_dir=$(ow_install_dir "$TARGET_ROOT")
init_path=$(ow_init_path "$TARGET_ROOT")

managed_install=no
managed_init=no
ow_is_managed_install "$TARGET_ROOT" && managed_install=yes
ow_is_managed_init "$TARGET_ROOT" && managed_init=yes

if [ "$managed_install" != "yes" ] && [ "$managed_init" != "yes" ]; then
    echo "No managed Generic OpenWrt install was detected; refusing to remove unrelated files." >&2
    exit 4
fi

if [ "$TARGET_ROOT" = "/" ] && [ "$TEST_MODE" != "1" ] && [ "$managed_init" = "yes" ] && [ -x "$init_path" ]; then
    "$init_path" stop >/dev/null 2>&1 || true
    "$init_path" disable >/dev/null 2>&1 || true
fi

[ "$managed_install" = "yes" ] && rm -rf "$install_dir"
[ "$managed_init" = "yes" ] && rm -f "$init_path"

printf '%s\n' "Generic OpenWrt uninstall"
printf '%s\n' "========================="
printf 'target_root: %s\n' "$TARGET_ROOT"
printf 'removed_install: %s\n' "$managed_install"
printf 'removed_init: %s\n' "$managed_init"
printf '%s\n' "backups_preserved: yes"
printf '%s\n' "UNINSTALL_OK"
