#!/bin/sh
# Independent finite-lived safety guard for MIPS runtime evaluation.
# The runner and watchdog use the SAME /proc/uptime anchor, not independent
# sleep counters. POSIX shell inherits ignored SIGHUP across SSH disconnect.
# Cannot survive reboot, kernel failure, SIGKILL or broad process-group kill.
stage="${1:-}"
run="${2:-}"
limit="${3:-}"
case "$run" in "$stage"/mips-smoke-run-*/*) exit 2 ;; "$stage"/mips-smoke-run-*) ;; *) exit 2 ;; esac
case "$limit" in ''|*[!0-9]*) exit 2 ;; esac
[ "$limit" -ge 60 ] && [ "$limit" -le 420 ] || exit 2
[ -r "$run/owner" ] && [ -r "$run/clock_start" ] || exit 2
owner=$(cat "$run/owner")
clock_start=$(cat "$run/clock_start")
case "$owner" in ''|*[!0-9]*) exit 2 ;; esac
case "$clock_start" in ''|*[!0-9]*) exit 2 ;; esac
. "$(dirname "$0")/../../lib/mips-runtime-health.sh"
elapsed=$(uu_mips_elapsed_since "$clock_start") || exit 2
# Parent must observe a live watcher after validation and before starting UU.
: > "$run/watchdog.ready" || exit 2
while :; do
    [ -f "$run/done" ] && exit 0
    [ -f "$run/cleanup.incomplete" ] && exit 8
    if ! kill -0 "$owner" 2>/dev/null; then
        echo "owner_exited: auto_cleanup" >> "$run/watchdog.log"
        break
    fi
    elapsed=$(uu_mips_elapsed_since "$clock_start") || {
        echo "watchdog_clock_unavailable: auto_cleanup" >> "$run/watchdog.log"
        break
    }
    [ "$elapsed" -lt "$limit" ] || break
    sleep 2
done
[ -f "$run/done" ] && exit 0
echo "watchdog_cleanup_at_seconds: $elapsed" >> "$run/watchdog.log"
sh "$(dirname "$0")/mips-runtime-stop.sh" "$stage" "$run" >> "$run/watchdog.log" 2>&1
