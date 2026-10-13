#!/bin/sh
# Validate the real guest telemetry formatter without launching a plugin.
# Catches broken line continuation or missing values before cloud QEMU runs.
set -eu
root=$(CDPATH= cd "$(dirname "$0")/.." && pwd) || exit 1
source_file="$root/labs/qemu/cross-arch/guest-runtime-probe.sh"
[ -f "$source_file" ] || exit 1

# Evaluate only the project's pure memory-formatting helper functions.
# The QEMU guard, official binaries, process launch and cleanup are untouched.
result=$(sh -c '
    helper=$(awk "/^mem_value\\(\\) \\{/ {copy=1} /^list_ours\\(\\) \\{/ {exit} copy {print}" "$1")
    [ -n "$helper" ] || exit 1
    eval "$helper"
    arch=fixture
    plugin_pid=""
    mem_sample before_start
' sh "$source_file") || {
    echo 'not ok - QEMU memory formatter fails' >&2
    exit 1
}
if ! printf '%s\n' "$result" |
    grep -Eq '^UU_LAB_MEM_SAMPLE arch=fixture phase=before_start total_kb=[1-9][0-9]* available_kb=[0-9]+ plugin_rss_kb=0 plugin_hwm_kb=0$'; then
    echo 'not ok - QEMU memory output has missing/malformed values' >&2
    exit 1
fi
echo 'ok - QEMU memory telemetry formatting'
