#!/bin/sh
# Cleanup of this stage's exact executables; never killall by program name.
# Target: OpenWrt fw4/nft. If restoring the ruleset is uncertain, fail closed.
stage="${1:-}"
run="${2:-}"
case "$stage" in /tmp/uu-wol-helper-*/*) echo "unsafe nested stage" >&2; exit 2 ;; /tmp/uu-wol-helper-*) ;; *) echo "unsafe stage" >&2; exit 2 ;; esac
case "$run" in "$stage"/mips-smoke-run-*/*) echo "unsafe nested run" >&2; exit 2 ;; "$stage"/mips-smoke-run-*) ;; *) echo "unsafe run directory" >&2; exit 2 ;; esac
[ -d "$run" ] && [ ! -L "$run" ] && [ -f "$run/firewall.before" ] && [ -f "$run/owner" ] || exit 2
[ ! -f "$run/done" ] || exit 0

if ! mkdir "$run/cleanup.lock" 2>/dev/null; then
    retries=0
    while [ "$retries" -lt 15 ]; do
        [ -f "$run/done" ] && exit 0
        [ -f "$run/cleanup.incomplete" ] && exit 8
        sleep 1
        retries=$((retries + 1))
    done
    echo "cleanup lock unresolved; inspect manually" >&2
    exit 8
fi
# The watchdog/main may race. Only the lock holder changes router state.
trap 'rmdir "$run/cleanup.lock" 2>/dev/null || true' EXIT HUP INT TERM
failed=no
managed_pids() {
    for proc in /proc/[0-9]*; do
        [ -r "$proc/stat" ] || continue
        exe=$(readlink "$proc/exe" 2>/dev/null || true)
        case "$exe" in
            "$stage/files/uuplugin"|"$stage/files/xuplugin-guardian")
                printf '%s\n' "${proc##*/}" ;;
        esac
    done
}
# Validate /proc/PID/exe again immediately before sending a signal to
# minimize risk from PID reuse and never touch another installation.
signal_managed() {
    action="$1"
    for proc in /proc/[0-9]*; do
        pid="${proc##*/}"
        exe=$(readlink "$proc/exe" 2>/dev/null || true)
        case "$exe" in
            "$stage/files/uuplugin"|"$stage/files/xuplugin-guardian")
                kill "-$action" "$pid" 2>/dev/null || true ;;
        esac
    done
}

signal_managed TERM
sleep 2
signal_managed KILL
sleep 1
if [ -n "$(managed_pids)" ]; then
    echo "CLEANUP_INCOMPLETE: staged UU processes remain" >&2
    failed=yes
fi
# A child might have daemonized into another executable or location.
# Never terminate unknown processes, but never declare cleanup complete.
if ps 2>/dev/null | grep -E '[u]uplugin|[x]uplugin-guardian|[u]uplugin_monitor|[x]netease-uu' >/dev/null 2>&1; then
    echo "CLEANUP_INCOMPLETE: unknown UU-related process remains" >&2
    failed=yes
fi
if ! nft -s list ruleset > "$run/firewall.after" 2>/dev/null; then
    echo "CLEANUP_INCOMPLETE: cannot verify nft firewall" >&2
    failed=yes
elif ! cmp -s "$run/firewall.before" "$run/firewall.after"; then
    echo "Firewall changed during temporary runtime; applying fw4 reload (may briefly interrupt network)" >&2
    if ! fw4 reload >/dev/null 2>&1 ||
       ! nft -s list ruleset > "$run/firewall.restored" 2>/dev/null ||
       ! cmp -s "$run/firewall.before" "$run/firewall.restored"; then
        echo "CLEANUP_INCOMPLETE: fw4 reload did not reproduce starting nft ruleset" >&2
        failed=yes
    else
        echo "firewall_restore: matched_after_fw4_reload"
    fi
else
    echo "firewall_restore: unchanged"
fi
if [ "$failed" = yes ]; then
    : > "$run/cleanup.incomplete"
    exit 8
fi
: > "$run/done"
echo "runtime_cleanup: pass"
exit 0
