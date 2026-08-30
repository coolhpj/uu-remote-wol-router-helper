#!/bin/sh

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/../.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/lib/checksum.sh"
. "$ROOT_DIR/lib/archive.sh"

STAGE_DIR="${UU_STAGE_DIR:-/tmp/uu-wol-helper-stage}"
TIMEOUT="${UU_SMOKE_TIMEOUT:-45}"
CONFIRM="${UU_RUNTIME_TEST_CONFIRM:-}"
ALLOW_STOP_EXISTING="${UU_ALLOW_STOP_EXISTING:-NO}"
LOG="/tmp/uu-wol-helper-smoke.log"

case "$STAGE_DIR" in
    /tmp/uu-wol-helper-*) ;;
    *)
        echo "Unsafe stage directory. UU_STAGE_DIR must match /tmp/uu-wol-helper-*" >&2
        exit 2
        ;;
esac

if [ "$CONFIRM" != "TEMPORARY_RUNTIME_CHANGE" ]; then
    cat >&2 <<'EOF'
Smoke-test is disabled by default.
It temporarily stops/starts UU processes but does not modify persistent files.
To run after reviewing the script, set:
  UU_RUNTIME_TEST_CONFIRM=TEMPORARY_RUNTIME_CHANGE
If an existing UU runtime is active, also set:
  UU_ALLOW_STOP_EXISTING=YES
EOF
    exit 64
fi

if ! sh "$ROOT_DIR/platforms/xiaoqiang/preflight.sh"; then
    echo "XiaoQiang preflight failed; smoke-test aborted." >&2
    exit 3
fi

metadata="$STAGE_DIR/metadata"
package="$STAGE_DIR/uu.tar.gz"
[ -f "$metadata" ] || { echo "Stage metadata is missing." >&2; exit 4; }
[ -f "$package" ] || { echo "Staged official package is missing." >&2; exit 4; }

stage_md5=$(sed -n 's/^md5=//p' "$metadata" | head -n 1)
if ! uu_verify_md5 "$package" "$stage_md5"; then
    echo "Staged package no longer matches the verified MD5." >&2
    exit 4
fi
if ! uu_validate_uu_package "$package"; then
    echo "Staged package structure is no longer valid." >&2
    exit 4
fi

for required in uuplugin xuplugin-guardian uu.conf xtables-nft-multi; do
    if [ ! -f "$STAGE_DIR/files/$required" ]; then
        echo "Staged file missing: $required" >&2
        exit 4
    fi
done

command -v killall >/dev/null 2>&1 || {
    echo "killall is required for reversible runtime smoke-test." >&2
    exit 5
}

find_existing_plugin_dir() {
    for dir in \
        /userdisk/appdata/2882303761518031252 \
        /jffs/uu \
        /data/uuplugin \
        /usr/share/uuplugin \
        /etc/uuplugin
    do
        if [ -f "$dir/uuplugin" ] && [ -f "$dir/uu.conf" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
    done
    return 1
}

is_uu_running() {
    ps 2>/dev/null | grep '[u]uplugin ./uu.conf' >/dev/null 2>&1
}

is_guardian_running() {
    ps 2>/dev/null | grep '[x]uplugin-guardian' >/dev/null 2>&1
}

is_monitor_running() {
    ps 2>/dev/null | grep '[u]uplugin_monitor' >/dev/null 2>&1
}

runtime_active() {
    is_uu_running || is_guardian_running || is_monitor_running
}

cloud_online() {
    if command -v netstat >/dev/null 2>&1; then
        netstat -anp 2>/dev/null | grep ':16000' | grep ESTABLISHED | grep uuplugin >/dev/null 2>&1
        return $?
    fi
    if command -v ss >/dev/null 2>&1; then
        ss -ntp 2>/dev/null | grep ':16000' | grep ESTAB | grep uuplugin >/dev/null 2>&1
        return $?
    fi
    return 1
}

previous_running="no"
previous_dir=""
temporary_started="no"
restored="no"

if runtime_active; then
    previous_running="yes"
    previous_dir=$(find_existing_plugin_dir 2>/dev/null || true)

    if [ "$ALLOW_STOP_EXISTING" != "YES" ]; then
        echo "Existing UU runtime detected. Refusing to stop it without UU_ALLOW_STOP_EXISTING=YES." >&2
        exit 65
    fi

    if [ -z "$previous_dir" ]; then
        echo "Existing UU runtime detected but no known restore directory was found." >&2
        exit 6
    fi

    if [ ! -x "$previous_dir/xnetease-uu" ]; then
        echo "Existing UU runtime has no verified xnetease-uu restore wrapper; refusing to stop it." >&2
        exit 6
    fi
fi

stop_uu_runtime() {
    killall uuplugin_monitor.sh 2>/dev/null || true
    killall uuplugin 2>/dev/null || true
    killall xuplugin-guardian 2>/dev/null || true
    sleep 2
}

restore_previous_runtime() {
    [ "$previous_running" = "yes" ] || return 0
    [ "$restored" = "no" ] || return 0

    stop_uu_runtime

    (cd "$previous_dir" && ./xnetease-uu plugon) >/tmp/uu-wol-helper-restore.log 2>&1 || return 1

    wait_elapsed=0
    while [ "$wait_elapsed" -lt 20 ]; do
        if is_uu_running; then
            restored="yes"
            return 0
        fi
        sleep 2
        wait_elapsed=$((wait_elapsed + 2))
    done

    return 1
}

cleanup() {
    if [ "$temporary_started" = "yes" ]; then
        stop_uu_runtime
    fi
    restore_previous_runtime >/dev/null 2>&1 || true
}
trap cleanup 0 HUP INT TERM

printf '%s\n' "XiaoQiang UU temporary smoke-test"
printf '%s\n' "================================="
printf 'stage_dir: %s\n' "$STAGE_DIR"
printf 'previous_runtime: %s\n' "$previous_running"
if [ -n "$previous_dir" ]; then
    printf 'restore_dir: %s\n' "$previous_dir"
fi
printf '%s\n' "persistent_changes: no"
printf '%s\n' "runtime_changes: temporary"

stop_uu_runtime

: > "$LOG"
(
    cd "$STAGE_DIR/files" || exit 1
    ./uuplugin ./uu.conf >>"$LOG" 2>&1
) &
temp_pid=$!
temporary_started="yes"

elapsed=0
passed="no"
while [ "$elapsed" -lt "$TIMEOUT" ]; do
    if ! kill -0 "$temp_pid" 2>/dev/null && ! is_uu_running; then
        echo "Temporary uuplugin exited before health checks passed." >&2
        break
    fi

    if is_uu_running && is_guardian_running && cloud_online; then
        passed="yes"
        break
    fi

    sleep 2
    elapsed=$((elapsed + 2))
done

printf 'uuplugin: %s\n' "$(is_uu_running && printf online || printf offline)"
printf 'guardian: %s\n' "$(is_guardian_running && printf online || printf offline)"
printf 'cloud_16000: %s\n' "$(cloud_online && printf online || printf offline)"
printf 'elapsed_seconds: %s\n' "$elapsed"

stop_uu_runtime
temporary_started="no"

if ! restore_previous_runtime; then
    echo "WARNING: temporary test ended, but automatic restore failed. Check /tmp/uu-wol-helper-restore.log." >&2
    exit 7
fi
trap - 0 HUP INT TERM

if [ "$passed" != "yes" ]; then
    echo "SMOKE_TEST_FAILED" >&2
    echo "Temporary runtime was stopped and previous runtime restoration was attempted." >&2
    exit 1
fi

printf '%s\n' "SMOKE_TEST_PASS"
if [ "$previous_running" = "yes" ]; then
    printf '%s\n' "Previous UU runtime was restored after the temporary test."
else
    printf '%s\n' "No previous UU runtime was active; temporary UU was stopped after the test."
fi
