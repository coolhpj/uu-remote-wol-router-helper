#!/bin/sh
# Independent finite-lived safety guard for MIPS runtime evaluation.
# POSIX shell ignores SIGHUP before exec and detaches standard streams.
# Cannot survive reboot, kernel failure, SIGKILL or broader process-group kill.
stage="${1:-}"
run="${2:-}"
limit="${3:-}"
case "$run" in "$stage"/mips-smoke-run-*/*) exit 2 ;; "$stage"/mips-smoke-run-*) ;; *) exit 2 ;; esac
case "$limit" in ''|*[!0-9]*) exit 2 ;; esac
[ "$limit" -ge 60 ] && [ "$limit" -le 420 ] || exit 2
[ -r "$run/owner" ] || exit 2
owner=$(cat "$run/owner")
case "$owner" in ''|*[!0-9]*) exit 2 ;; esac
# Parent must observe a live watcher after validation and before starting UU.
: > "$run/watchdog.ready" || exit 2
elapsed=0
while [ "$elapsed" -lt "$limit" ]; do
    [ -f "$run/done" ] && exit 0
    [ -f "$run/cleanup.incomplete" ] && exit 8
    if ! kill -0 "$owner" 2>/dev/null; then
        echo "owner_exited: auto_cleanup" >> "$run/watchdog.log"
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done
[ -f "$run/done" ] && exit 0
echo "watchdog_cleanup_at_seconds: $elapsed" >> "$run/watchdog.log"
sh "$(dirname "$0")/mips-runtime-stop.sh" "$stage" "$run" >> "$run/watchdog.log" 2>&1
