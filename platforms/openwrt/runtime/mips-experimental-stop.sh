#!/bin/sh
# Never terminate a process based on its name alone.
# Only terminate binaries executed from our dedicated temporary stage path.
set -u
STAGE_DIR="/tmp/uu-wol-helper-mips-persist"
owned_pids() {
    for path in /proc/[0-9]*/exe; do
        exe=$(readlink "$path" 2>/dev/null || true)
        case "$exe" in
            "$STAGE_DIR/files/uuplugin"|"$STAGE_DIR/files/xuplugin-guardian")
                pid="${path#/proc/}"
                printf '%s\n' "${pid%/exe}"
                ;;
        esac
    done
}
signal_owned() {
    sig="$1"
    for pid in $(owned_pids); do
        exe=$(readlink "/proc/$pid/exe" 2>/dev/null || true)
        case "$exe" in
            "$STAGE_DIR/files/uuplugin"|"$STAGE_DIR/files/xuplugin-guardian")
                kill "-$sig" "$pid" 2>/dev/null || true ;;
        esac
    done
}
signal_owned TERM
sleep 2
signal_owned KILL
sleep 1
[ -z "$(owned_pids)" ] || {
    echo "MIPS_STOP_INCOMPLETE: owned process still alive" >&2
    exit 8
}
# A separately installed UU service may now be active; do not alter its
# dynamic firewall entries. Detect it, but never kill it.
if ps 2>/dev/null | grep -E '[u]uplugin|[x]uplugin-guardian|[u]uplugin_monitor' >/dev/null 2>&1; then
    echo "MIPS_STOP_INCOMPLETE: an unrelated UU process is still active" >&2
    exit 8
fi

# Plugin-specific firewall entries may require fw4 reload. Avoid touching
# unrelated rules when no XU_ marker exists; never globally flush tables.
if command -v nft >/dev/null 2>&1; then
    tables=$(nft list tables 2>/dev/null) || {
        echo "MIPS_STOP_INCOMPLETE: nft inspection unavailable" >&2
        exit 8
    }
    if printf '%s\n' "$tables" | grep 'XU_' >/dev/null 2>&1; then
        if ! command -v fw4 >/dev/null 2>&1 || ! fw4 reload; then
            echo "MIPS_STOP_INCOMPLETE: cannot reload firewall" >&2
            exit 8
        fi
        tables=$(nft list tables 2>/dev/null) || exit 8
        if printf '%s\n' "$tables" | grep 'XU_' >/dev/null 2>&1; then
            echo "MIPS_STOP_INCOMPLETE: plugin firewall entries remain" >&2
            exit 8
        fi
        echo "MIPS_STOP_FIREWALL_RELOADED"
    fi
else
    echo "MIPS_STOP_INCOMPLETE: nft required for verified cleanup" >&2
    exit 8
fi
echo "MIPS_STOP_PASS"
