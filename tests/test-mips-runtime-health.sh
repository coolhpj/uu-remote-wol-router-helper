#!/bin/sh
set -eu
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd) || exit 1
. "$ROOT/lib/mips-runtime-health.sh"
fail() { echo "not ok - $*" >&2; exit 1; }
ok() { echo "ok - $*"; }

uu_mips_runtime_window_pass 300 300 no yes yes yes || fail "full sustained connection should pass"
ok "full window with current guardian/cloud and live plugin passes"

if uu_mips_runtime_window_pass 264 300 yes yes yes no; then fail "historical connected flags may not mask early exit"; fi
ok "264s early plugin exit cannot be classified as health pass"

if uu_mips_runtime_window_pass 300 300 no yes no yes; then fail "cloud lost at end must fail"; fi
ok "cloud connection lost at end fails"

if uu_mips_runtime_window_pass 300 300 no no yes yes; then fail "guardian lost at end must fail"; fi
ok "guardian lost at end fails"

if uu_mips_runtime_window_pass 300 300 no yes yes no; then fail "plugin not alive must fail"; fi
ok "plugin no longer alive at end fails"

if uu_mips_runtime_window_pass 180 300 no yes yes yes; then fail "incomplete duration must fail"; fi
ok "interrupted or shortened test cannot pass"

# The Y1 report showed 268-290 counted sleep seconds despite ~330 seconds
# of wall clock. Simulate scan overhead without waiting for five minutes.
[ "$(uu_mips_elapsed_between 1000 1331)" = 331 ] || fail "elapsed must include polling overhead"
[ 331 -ge 330 ] || fail "independent watchdog deadline"
[ 280 -lt 300 ] || fail "synthetic naive sleep counter reproduces false early exit"
if uu_mips_elapsed_between 1331 1000 >/dev/null 2>&1; then fail "clock reset must fail"; fi
if uu_mips_elapsed_between not-a-time 1331 >/dev/null 2>&1; then fail "invalid clock must fail"; fi
ok "real elapsed time includes simulated heavy polling, unlike sleep counter"

# Kernel clock reader must work with the small BusyBox awk /proc/uptime format.
fixture="/tmp/uu-mips-uptime-fixture-$$"
printf '1234.67 987.65\n' > "$fixture"
[ "$(uu_mips_uptime_seconds "$fixture")" = 1234 ] || fail "parse procfs uptime"
printf 'invalid 987.65\n' > "$fixture"
if uu_mips_uptime_seconds "$fixture" >/dev/null 2>&1; then fail "invalid uptime must fail"; fi
rm -f "$fixture"
ok "monotonic clock parser accepts procfs and rejects invalid input"

echo "all MIPS runtime health classification tests passed"
