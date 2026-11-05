#!/bin/sh
# Separate procd-managed watcher; capture an identifier only when first created.
set -u
APP_DIR=/usr/lib/uu-mips-wol-helper
if [ "${UU_TEST_MODE:-0}" = 1 ]; then
    APP_DIR="${UU_MIPS_APP_DIR:-$APP_DIR}"
else
    case "$0" in
        /usr/lib/uu-mips-wol-helper/uuid-watch.sh) ;;
        /usr/lib/uu-mips-wol-helper-v2/uuid-watch.sh) APP_DIR=/usr/lib/uu-mips-wol-helper-v2 ;;
        *) echo "MIPS_UUID_WATCH_UNOWNED_PATH" >&2; exit 66 ;;
    esac
fi
[ -f "$APP_DIR/install.meta" ] || exit 66
grep -qx 'managed_by=uu-remote-wol-router-helper-mips-beta' "$APP_DIR/install.meta" || exit 66
. "$APP_DIR/uuid-state.sh"
warned=0
while :; do
    uu_uuid_backup_once
    rc=$?
    if [ "$rc" -eq 2 ] && [ "$warned" -eq 0 ]; then
        echo "MIPS_UUID_WATCH_WARNING: state not persisted; identity protected" >&2
        warned=1
    fi
    sleep 15
done
