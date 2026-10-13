#!/bin/sh
# Stop ONLY this managed install's guardian. Never killall by basename.
# Invoked by /etc/init.d/uu-wol-helper after procd stops the managed main.
set -u

TARGET=/usr/lib/uu-wol-helper/xuplugin-guardian
if [ -n "${UU_TEST_GUARDIAN_PATH:-}" ]; then
    # Test-only substitute. Real devices can never redirect the target.
    [ "${UU_TEST_MODE:-0}" = 1 ] || {
        echo "Guardian stop: test path forbidden in production" >&2
        exit 2
    }
    case "$UU_TEST_GUARDIAN_PATH" in
        /tmp/uu-wol-helper-test-*/xuplugin-guardian)
            TARGET=$UU_TEST_GUARDIAN_PATH ;;
        *)
            echo "Guardian stop: unsafe test path" >&2
            exit 2 ;;
    esac
fi

command -v readlink >/dev/null 2>&1 || {
    echo "Guardian stop: readlink unavailable; no signal sent" >&2
    exit 3
}

# Read /proc/PID/exe before every signal, rather than matching ps names or
# cached PIDs. This avoids terminating a foreign uuplugin installation.
owned_pids() {
    for proc in /proc/[0-9]*; do
        [ -r "$proc/stat" ] || continue
        exe=$(readlink "$proc/exe" 2>/dev/null || true)
        [ "$exe" = "$TARGET" ] || continue
        printf '%s\n' "${proc##*/}"
    done
}
signal_owned() {
    signal=$1
    for pid in $(owned_pids); do
        exe=$(readlink "/proc/$pid/exe" 2>/dev/null || true)
        [ "$exe" = "$TARGET" ] || continue
        kill "-$signal" "$pid" 2>/dev/null || true
    done
}
signal_owned TERM
sleep 1
signal_owned KILL
sleep 1

if [ -n "$(owned_pids)" ]; then
    echo "Guardian stop: managed process still active; manual inspection required" >&2
    exit 8
fi
echo GUARDIAN_OWNED_STOP_PASS
