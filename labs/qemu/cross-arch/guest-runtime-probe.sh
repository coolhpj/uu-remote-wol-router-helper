#!/bin/sh
# Disposable QEMU guest ONLY. Never use on a physical router.
# Expects official archive to have been MD5-verified and unpacked in /tmp.
# A separate watchdog kills only executables under the exact staging path.
set -eu
arch="${1:-}"
case "$arch" in x86_64|mipsel) ;; *) echo UU_RUNTIME_BAD_ARCH >&2; exit 2 ;; esac
[ "${UU_QEMU_RUNTIME_ONLY:-}" = DISPOSABLE_QEMU_GUEST ] || {
    echo UU_RUNTIME_QEMU_GUARD_MISSING >&2; exit 2
}
case "$arch" in
    x86_64) grep -qi qemu /sys/class/dmi/id/sys_vendor 2>/dev/null || {
        echo UU_RUNTIME_NOT_QEMU >&2; exit 2; } ;;
    mipsel) grep -qi malta /proc/cpuinfo 2>/dev/null || {
        echo UU_RUNTIME_NOT_MALTA >&2; exit 2; } ;;
esac
stage=/tmp/uu-lab-extracted
[ -d "$stage" ] && [ ! -L "$stage" ] || exit 2
[ -x "$stage/uuplugin" ] && [ -x "$stage/xuplugin-guardian" ] || {
    echo UU_RUNTIME_MISSING_EXE >&2; exit 3
}
[ -f "$stage/uu.conf" ] && [ ! -L "$stage/uu.conf" ] || exit 3
[ "$(uname -m)" = "$(case "$arch" in x86_64) echo x86_64;;mipsel) echo mips;;esac)" ] || exit 3
for tool in readlink ps kill sleep nft fw4; do command -v "$tool" >/dev/null 2>&1 || {
    echo "UU_RUNTIME_PREREQ_MISSING $tool" >&2; exit 4
}; done
nft list tables > /tmp/uu-lab-before-tables 2>/dev/null || {
    echo UU_RUNTIME_NFT_PREREQ_FAILED >&2; exit 4
}
if grep -q XU_ /tmp/uu-lab-before-tables; then
    echo UU_RUNTIME_FOREIGN_FIREWALL_DETECTED >&2
    exit 5
fi

# No default route during executable test: no cloud registration or internet
# traffic. Only the connected QEMU guest-local subnet remains available.
if ip -4 route show default | grep -q '^default' ||
   ip -6 route show default | grep -q '^default'; then
    echo UU_RUNTIME_OUTBOUND_ROUTE_PRESENT >&2; exit 5
fi

# Numeric snapshots are guest observations, NOT a claim about full RAM peak.
# Available memory reflects the entire guest (cache/kernel included); VmHWM
# records only this process's sampled high-water RSS before cleanup.
mem_value() {
    awk -v field="$1" '$1 == field {print $2; exit}' /proc/meminfo
}
process_value() {
    field="$1"
    [ -n "${plugin_pid:-}" ] && [ -r "/proc/$plugin_pid/status" ] || { echo 0; return; }
    awk -v field="$field:" '$1 == field {print $2; exit}' "/proc/$plugin_pid/status"
}
mem_sample() {
    phase="$1"
    total=$(mem_value 'MemTotal:')
    available=$(mem_value 'MemAvailable:')
    [ -n "$total" ] && [ -n "$available" ] || {
        echo UU_LAB_MEMORY_METRIC_MISSING >&2; return 1
    }
    rss=$(process_value VmRSS)
    hwm=$(process_value VmHWM)
    printf 'UU_LAB_MEM_SAMPLE arch=%s phase=%s total_kb=%s available_kb=%s plugin_rss_kb=%s plugin_hwm_kb=%s\n' \\
        "$arch" "$phase" "$total" "$available" "${rss:-0}" "${hwm:-0}"
}

list_ours() {
    for link in /proc/[0-9]*/exe; do
        target=$(readlink "$link" 2>/dev/null || true)
        case "$target" in
            "$stage/uuplugin"|"$stage/xuplugin-guardian")
                pid=${link#/proc/}; pid=${pid%/exe}
                printf '%s\n' "$pid" ;;
        esac
    done
}
stop_ours() {
    for sig in TERM KILL; do
        for pid in $(list_ours); do
            kill "-$sig" "$pid" 2>/dev/null || true
        done
        sleep 1
    done
}
[ -z "$(list_ours)" ] || { echo UU_RUNTIME_ALREADY_RUNNING >&2; exit 5; }

watchdog_pid=''
plugin_pid=''
mem_sample before_start
cleanup() {
    rc=$?
    trap - EXIT HUP INT TERM
    stop_ours
    if [ -n "$watchdog_pid" ]; then
        kill "$watchdog_pid" 2>/dev/null || true
    fi
    # Disposable guest only. fw4 reload reverses any temporary XU_ rule state.
    fw4 reload >/tmp/uu-lab-fw4-clean.log 2>&1 || rc=8
    [ -z "$(list_ours)" ] || rc=8
    nft list tables >/tmp/uu-lab-after-tables 2>/dev/null || rc=8
    if grep -q XU_ /tmp/uu-lab-after-tables 2>/dev/null; then
        echo UU_RUNTIME_FIREWALL_RESIDUE >&2
        rc=8
    fi
    plugin_pid=''
    mem_sample after_cleanup || rc=8
    if [ "$rc" -eq 0 ]; then
        echo UU_LAB_RUNTIME_CLEAN_PASS
    else
        echo "UU_LAB_RUNTIME_FAILED code=$rc" >&2
    fi
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

# Independent final defense against a stuck parent shell. Watchdog operates
# only within the guest and only on the checked official staged executables.
(
    sleep 32
    stop_ours
) </dev/null >/tmp/uu-lab-watchdog.log 2>&1 &
watchdog_pid=$!

(
    cd "$stage" || exit 1
    exec ./uuplugin ./uu.conf
) </dev/null >/tmp/uu-lab-runtime.log 2>&1 &
plugin_pid=$!
echo UU_LAB_RUNTIME_EXEC_ATTEMPTED
sleep 4
exe=$(readlink "/proc/$plugin_pid/exe" 2>/dev/null || true)
if [ "$exe" != "$stage/uuplugin" ]; then
    echo UU_RUNTIME_EARLY_EXIT_OR_WRONG_BINARY >&2
    exit 6
fi
echo UU_LAB_RUNTIME_ALIVE_AT_4S
mem_sample after_4s
sleep 8
exe=$(readlink "/proc/$plugin_pid/exe" 2>/dev/null || true)
if [ "$exe" != "$stage/uuplugin" ]; then
    echo UU_RUNTIME_EXITED_BEFORE_12S >&2
    exit 7
fi
echo UU_LAB_RUNTIME_ALIVE_AT_12S
mem_sample after_12s
# cleanup() validates no owned executables or XU_ firewall tables remain.
exit 0
