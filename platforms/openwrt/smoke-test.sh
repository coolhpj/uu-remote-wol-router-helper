#!/bin/sh

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/../.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/lib/checksum.sh"
. "$ROOT_DIR/lib/archive.sh"
. "$ROOT_DIR/lib/evidence.sh"
. "$ROOT_DIR/lib/channel.sh"

STAGE_DIR="${UU_STAGE_DIR:-/tmp/uu-wol-helper-stage}"
TIMEOUT="${UU_SMOKE_TIMEOUT:-45}"
CONFIRM="${UU_RUNTIME_TEST_CONFIRM:-}"
LOG="$STAGE_DIR/smoke.log"

case "$STAGE_DIR" in
    /tmp/uu-wol-helper-*) ;;
    *)
        echo "Unsafe stage directory. UU_STAGE_DIR must match /tmp/uu-wol-helper-*" >&2
        exit 2
        ;;
esac

if [ "$CONFIRM" != "TEMPORARY_RUNTIME_CHANGE" ]; then
    cat >&2 <<'EOF'
Generic OpenWrt smoke-test is disabled by default.
It temporarily starts/stops the staged UU runtime but does not install it.
To run after reviewing the script, set:
  UU_RUNTIME_TEST_CONFIRM=TEMPORARY_RUNTIME_CHANGE
If any existing UU runtime is detected, this draft refuses to continue.
EOF
    exit 64
fi

if ! sh "$ROOT_DIR/platforms/openwrt/preflight.sh"; then
    echo "Generic OpenWrt preflight failed; smoke-test aborted." >&2
    exit 3
fi

if [ "$(id -u 2>/dev/null || printf 1)" != "0" ]; then
    echo "Root is required for the temporary runtime smoke-test." >&2
    exit 3
fi

metadata="$STAGE_DIR/metadata"
package="$STAGE_DIR/uu.tar.gz"
[ -f "$metadata" ] || { echo "Stage metadata is missing." >&2; exit 4; }
[ -f "$package" ] || { echo "Staged official package is missing." >&2; exit 4; }

stage_channel=$(sed -n 's/^channel=//p' "$metadata" | head -n 1)
stage_md5=$(sed -n 's/^md5=//p' "$metadata" | head -n 1)
arch=$(uname -m 2>/dev/null || printf 'unknown')
expected_channel=$(uu_openwrt_channel_for_arch "$arch" 2>/dev/null || true)

[ -n "$expected_channel" ] || {
    echo "No confirmed official OpenWrt channel for this architecture." >&2
    exit 4
}
[ "$stage_channel" = "$expected_channel" ] || {
    printf 'Staged channel mismatch: expected=%s actual=%s\n' "$expected_channel" "$stage_channel" >&2
    exit 4
}

uu_verify_md5 "$package" "$stage_md5" || {
    echo "Staged package no longer matches the verified MD5." >&2
    exit 4
}
uu_validate_uu_package "$package" || {
    echo "Staged package structure is no longer valid." >&2
    exit 4
}

for required in uuplugin xuplugin-guardian uu.conf xtables-nft-multi; do
    [ -f "$STAGE_DIR/files/$required" ] || {
        echo "Staged file missing: $required" >&2
        exit 4
    }
done

have_cmd() {
    name="$1"
    command -v "$name" >/dev/null 2>&1 && return 0
    for dir in /bin /sbin /usr/bin /usr/sbin; do
        [ -x "$dir/$name" ] && return 0
    done
    return 1
}

have_cmd killall || { echo "killall is required." >&2; exit 5; }
if ! have_cmd netstat && ! have_cmd ss; then
    echo "netstat or ss is required for the cloud health check." >&2
    exit 5
fi

is_uu_running() {
    ps 2>/dev/null | grep '[u]uplugin .*uu.conf' >/dev/null 2>&1
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
    if have_cmd netstat; then
        netstat -anp 2>/dev/null | grep ':16000' | grep ESTABLISHED | grep uuplugin >/dev/null 2>&1
        return $?
    fi
    ss -ntp 2>/dev/null | grep ':16000' | grep ESTAB | grep uuplugin >/dev/null 2>&1
}

if runtime_active; then
    echo "Existing UU runtime detected. Generic OpenWrt smoke-test refuses to stop or replace it." >&2
    exit 65
fi

uu_clear_smoke_pass "$STAGE_DIR" || {
    echo "Unable to clear stale smoke evidence." >&2
    exit 4
}

temporary_started="no"

stop_temporary_runtime() {
    killall uuplugin 2>/dev/null || true
    killall xuplugin-guardian 2>/dev/null || true
    sleep 2
}

cleanup() {
    if [ "$temporary_started" = "yes" ]; then
        stop_temporary_runtime
    fi
}
trap cleanup 0 HUP INT TERM

printf '%s\n' "Generic OpenWrt UU temporary smoke-test"
printf '%s\n' "======================================"
printf 'stage_dir: %s\n' "$STAGE_DIR"
printf 'architecture: %s\n' "$arch"
printf 'channel: %s\n' "$stage_channel"
printf '%s\n' "persistent_changes: no"
printf '%s\n' "runtime_changes: temporary"

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

stop_temporary_runtime
temporary_started="no"
trap - 0 HUP INT TERM

if [ "$passed" != "yes" ]; then
    echo "SMOKE_TEST_FAILED" >&2
    echo "Temporary UU runtime was stopped; no persistent configuration was written." >&2
    exit 1
fi

if ! uu_write_smoke_pass "$STAGE_DIR" openwrt "$stage_md5"; then
    echo "Smoke-test passed but evidence marker could not be written." >&2
    exit 7
fi

printf '%s\n' "SMOKE_TEST_PASS"
printf '%s\n' "Temporary UU runtime was stopped after the test."
printf '%s\n' "A stage-MD5-bound smoke-pass marker was written for the future persistent-install gate."
