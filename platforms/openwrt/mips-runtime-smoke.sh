#!/bin/sh
# Experimental Lenovo Y1 / OpenWrt MIPS single-session runtime evaluation.
# NO persistent installation and NO automatic install unlock.
# Requires the user at the router (local console/access) and an explicit opt-in.

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/../.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/lib/channel.sh"
. "$ROOT_DIR/lib/evidence.sh"
. "$ROOT_DIR/lib/checksum.sh"
. "$ROOT_DIR/lib/archive.sh"
. "$ROOT_DIR/lib/elf.sh"
. "$ROOT_DIR/lib/mips-runtime-health.sh"

STAGE_DIR="${UU_STAGE_DIR:-/tmp/uu-wol-helper-stage}"
CONFIRM="${UU_MIPS_RUNTIME_CONFIRM:-}"
DURATION="${UU_MIPS_RUNTIME_SECONDS:-240}"

case "$STAGE_DIR" in /tmp/uu-wol-helper-*/*) echo "Stage directory must be a direct /tmp child" >&2; exit 2 ;; /tmp/uu-wol-helper-*) ;; *)
    echo "Unsafe stage directory" >&2; exit 2 ;; esac
if [ "$CONFIRM" != "ONE_TIME_MIPS_TEST_WITH_LOCAL_RECOVERY" ]; then
    echo "MIPS temporary runtime is disabled by default (requires local router recovery access)." >&2
    echo "Use UU_MIPS_RUNTIME_CONFIRM=ONE_TIME_MIPS_TEST_WITH_LOCAL_RECOVERY only for this temporary test." >&2
    echo "A firewall reload may occur on exit and briefly interrupt network connectivity." >&2
    exit 64
fi
case "$DURATION" in ''|*[!0-9]*) echo "Invalid test duration" >&2; exit 2 ;; esac
if [ "$DURATION" -lt 120 ] || [ "$DURATION" -gt 360 ]; then
    echo "Test duration must be between 120 and 360 seconds" >&2
    exit 2
fi
[ "$(id -u 2>/dev/null || printf 1)" = 0 ] || { echo "Root required" >&2; exit 3; }
arch=$(uu_openwrt_detect_arch 2>/dev/null || printf unknown)
[ "$arch" = "mipsel_24kc" ] || { echo "MIPS architecture metadata not independently confirmed" >&2; exit 3; }
sh "$ROOT_DIR/platforms/openwrt/preflight.sh" >/dev/null 2>&1 || { echo "OpenWrt preflight failed" >&2; exit 3; }
for tool in nft fw4 readlink cmp ps netstat awk grep sed sleep kill; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'Runtime safety prerequisite missing: %s\n' "$tool" >&2; exit 5; }
done
[ -d /proc ] && [ -r "/proc/$$/exe" ] || { echo "Readable /proc required" >&2; exit 5; }
[ -d "$STAGE_DIR" ] && [ ! -L "$STAGE_DIR" ] || { echo "Stage directory missing or unsafe" >&2; exit 4; }
canonical_stage=$(CDPATH= cd -P "$STAGE_DIR" 2>/dev/null && pwd) || exit 4
[ "$canonical_stage" = "$STAGE_DIR" ] || { echo "Stage path must not be a symlink" >&2; exit 4; }
[ -f "$STAGE_DIR/metadata" ] && [ -f "$STAGE_DIR/uu.tar.gz" ] || {
    echo "Staged official package missing; run 'sh uu-helper.sh stage auto' first" >&2; exit 4;
}
channel=$(sed -n 's/^channel=//p' "$STAGE_DIR/metadata" | head -n 1)
md5=$(sed -n 's/^md5=//p' "$STAGE_DIR/metadata" | head -n 1)
[ "$channel" = "openwrt-mipsel" ] && uu_evidence_validate_md5 "$md5" &&
    uu_verify_md5 "$STAGE_DIR/uu.tar.gz" "$md5" &&
    uu_validate_uu_package "$STAGE_DIR/uu.tar.gz" &&
    uu_check_stage_mipsel_elf "$STAGE_DIR" || { echo "Staged package failed full verification" >&2; exit 4; }
for file in uuplugin xuplugin-guardian xtables-nft-multi uu.conf; do
    [ -f "$STAGE_DIR/files/$file" ] && [ ! -L "$STAGE_DIR/files/$file" ] || {
        echo "Stage contains missing/symlinked file" >&2; exit 4;
    }
done
for executable in uuplugin xuplugin-guardian xtables-nft-multi; do
    [ -x "$STAGE_DIR/files/$executable" ] || {
        printf 'Staged executable is not executable: %s\n' "$executable" >&2
        exit 4
    }
done

# Never replace or stop an existing runtime. Do not start while any previously
# detected XU_ firewall markers exist (even if they belong to someone else).
if ps 2>/dev/null | grep -E '[u]uplugin|[x]uplugin-guardian|[u]uplugin_monitor|[x]netease-uu' >/dev/null 2>&1; then
    echo "Existing UU process found, refuse temporary runtime" >&2
    exit 65
fi
for proc in /proc/[0-9]*/exe; do
    case "$(readlink "$proc" 2>/dev/null || true)" in
        */uuplugin|*/xuplugin-guardian) echo "UU process already active" >&2; exit 65 ;;
    esac
done
table_list=$(nft list tables 2>/dev/null) || { echo "nft list tables failed" >&2; exit 5; }
if printf '%s\n' "$table_list" | grep 'XU_' >/dev/null 2>&1; then
    echo "Existing XU_ firewall tables detected; refuse to touch them" >&2
    exit 65
fi

# Single-owner lock across sessions; a failed cleanup deliberately keeps
# evidence for local recovery rather than claiming success.
lock="$STAGE_DIR/mips-smoke.lock"
if ! mkdir "$lock" 2>/dev/null; then
    echo "A previous MIPS test/cleanup lock exists; inspect before retrying" >&2
    exit 65
fi
run="$STAGE_DIR/mips-smoke-run-$$"
if ! (umask 077; mkdir "$run"); then
    rmdir "$lock" 2>/dev/null || true
    echo "Cannot allocate smoke run directory" >&2
    exit 4
fi
printf '%s\n' "$$" > "$run/owner"
printf '%s\n' "$run" > "$lock/run"
if ! nft -s list ruleset > "$run/firewall.before" 2>/dev/null || [ ! -s "$run/firewall.before" ]; then
    rm -f "$lock/run"
    rmdir "$lock" 2>/dev/null || true
    echo "Cannot snapshot nft ruleset; no plugin started" >&2
    exit 5
fi
if ! uu_clear_smoke_pass "$STAGE_DIR"; then
    rm -f "$lock/run"
    rmdir "$lock" 2>/dev/null || true
    echo "Unable to invalidate old smoke evidence" >&2
    exit 5
fi

active=no
cleanup() {
    saved=$?
    trap - EXIT HUP INT TERM
    if [ "$active" = yes ]; then
        if sh "$ROOT_DIR/platforms/openwrt/mips-runtime-stop.sh" "$STAGE_DIR" "$run"; then
            if [ "$saved" -eq 0 ]; then
                echo "MIPS_TEMPORARY_RUNTIME_CLEANUP_PASS"
            fi
        else
            echo "CLEANUP_INCOMPLETE: do not install; router may require local firewall recovery" >&2
            saved=8
        fi
        if [ -f "$run/done" ]; then
            rm -f "$lock/run"
            rmdir "$lock" 2>/dev/null || true
        fi
    else
        rm -f "$lock/run"
        rmdir "$lock" 2>/dev/null || true
    fi
    exit "$saved"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

# Start watchdog BEFORE the plugin. BusyBox builds may not ship 'nohup'.
# POSIX sh supports ignoring SIGHUP as a shell builtin. The detached child
# inherits SIG_IGN across exec and has no SSH terminal stdin/stdout/stderr.
# Neither this nor nohup can survive reboot, SIGKILL, or network reconfiguration.
active=yes
(
    trap '' HUP
    exec sh "$ROOT_DIR/platforms/openwrt/mips-runtime-watchdog.sh" "$STAGE_DIR" "$run" "$((DURATION + 30))"
) </dev/null >>"$run/watchdog.log" 2>&1 &
watchdog_pid=$!
watchdog_ready=no
for attempt in 1 2 3 4 5; do
    if [ -f "$run/watchdog.ready" ] && kill -0 "$watchdog_pid" 2>/dev/null; then
        watchdog_ready=yes
        break
    fi
    sleep 1
done
if [ "$watchdog_ready" != yes ]; then
    echo "Independent watchdog failed its readiness handshake; no plugin started" >&2
    exit 5
fi

echo "MIPS temporary runtime session"
echo "================================"
echo "persistent_install: disabled"
echo "duration_seconds: $DURATION"
echo "local_recovery_access: required"
echo "cloud_check: netstat tcp 16000"
echo "firewall_snapshot: captured"
echo "watchdog: running"
echo "run_directory: $run"

# exec ensures the direct child PID belongs to the exact staged plugin.
(
    cd "$STAGE_DIR/files" || exit 1
    exec ./uuplugin ./uu.conf >>"$run/plugin.log" 2>&1
) &
plugin_pid=$!
printf '%s\n' "$plugin_pid" > "$run/started_pid"
elapsed=0
cloud_online=no
guardian_online=no
cloud_seen=no
guardian_seen=no
announced=no
plugin_exited_early=no
while [ "$elapsed" -lt "$DURATION" ]; do
    if ! kill -0 "$plugin_pid" 2>/dev/null; then
        echo "Plugin launch process ended before test window completed" >&2
        plugin_exited_early=yes
        cloud_online=no
        guardian_online=no
        break
    fi
    # These are CURRENT observations, not sticky "ever online" flags.
    # A momentary successful handshake cannot prove continued runtime health.
    cloud_online=no
    guardian_online=no
    if netstat -anp 2>/dev/null | grep ':16000' | grep ESTABLISHED | grep uuplugin >/dev/null 2>&1; then
        cloud_online=yes
        cloud_seen=yes
    fi
    for proc in /proc/[0-9]*/exe; do
        if [ "$(readlink "$proc" 2>/dev/null || true)" = "$STAGE_DIR/files/xuplugin-guardian" ]; then
            guardian_online=yes
            guardian_seen=yes
            break
        fi
    done
    if [ "$cloud_online" = yes ] && [ "$guardian_online" = yes ] && [ "$announced" = no ]; then
        echo "cloud_and_guardian_ready: yes"
        echo "You may test remote WOL from mobile data during the remaining window."
        announced=yes
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done
printf 'guardian_ever_online: %s\n' "$guardian_seen"
printf 'cloud_16000_ever_online: %s\n' "$cloud_seen"
printf 'guardian_at_end: %s\n' "$guardian_online"
printf 'cloud_16000_at_end: %s\n' "$cloud_online"
printf 'plugin_exited_early: %s\n' "$plugin_exited_early"
printf 'elapsed_seconds: %s\n' "$elapsed"
echo "mobile_wol: requires user's real phone/PC observation"
plugin_still_running=no
if kill -0 "$plugin_pid" 2>/dev/null; then
    plugin_still_running=yes
fi
if uu_mips_runtime_window_pass "$elapsed" "$DURATION" "$plugin_exited_early" "$guardian_online" "$cloud_online" "$plugin_still_running"; then
    echo "MIPS_RUNTIME_HEALTH_PASS"
    exit 0
fi
echo "MIPS_RUNTIME_HEALTH_INCOMPLETE" >&2
exit 1
