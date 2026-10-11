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

echo "all MIPS runtime health classification tests passed"
