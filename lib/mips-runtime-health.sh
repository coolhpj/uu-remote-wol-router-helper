#!/bin/sh
# Pure result predicate for the experimental one-session MIPS runtime test.
# A previously observed cloud/guardian connection is never sufficient.
uu_mips_runtime_window_pass() {
    [ "$1" -ge "$2" ] &&
        [ "$3" = no ] &&
        [ "$4" = yes ] &&
        [ "$5" = yes ] &&
        [ "$6" = yes ]
}

# Read the same monotonic-ish kernel uptime from both the foreground runner
# and its independently scheduled watcher. No dependence on wall-clock/NTP.
# OpenWrt /proc/uptime is available with procfs, including minimal BusyBox.
uu_mips_uptime_seconds() {
    awk 'NR == 1 {
        if ($1 !~ /^[0-9]+([.][0-9]+)?$/) exit 2
        printf "%.0f\n", int($1)
        seen = 1
        exit
    } END {if (!seen) exit 2}' "${1:-/proc/uptime}"
}

# Pure, testable elapsed calculation; rejects reversed/rebooted clocks.
uu_mips_elapsed_between() {
    start="$1"
    now="$2"
    case "$start:$now" in *[!0-9:]*|:*|*:) return 1 ;; esac
    [ "$now" -ge "$start" ] || return 1
    printf '%s\n' "$((now - start))"
}

# Fails closed if kernel uptime disappears, resets, or cannot be read.
uu_mips_elapsed_since() {
    start="$1"
    now=$(uu_mips_uptime_seconds) || return 1
    uu_mips_elapsed_between "$start" "$now"
}
