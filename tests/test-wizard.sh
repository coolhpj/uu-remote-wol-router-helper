#!/bin/sh
# Read-only policy/menu tests, plus a PTY smoke test on a non-router host.
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd) || exit 1
. "$ROOT/lib/wizard-policy.sh"
fail() { printf 'not ok - %s\n' "$*" >&2; exit 1; }
ok() { printf 'ok - %s\n' "$*"; }

[ "$(uu_wizard_mode asuswrt aarch64)" = official ] || fail "ASUS native official route"
[ "$(uu_wizard_mode unknown unknown)" = collect ] || fail "unknown hardware collect-only"
[ "$(uu_wizard_mode openwrt mipsel_24kc)" = experimental ] || fail "MIPS experimental route"
[ "$(uu_wizard_mode openwrt x86_64)" = candidate ] || fail "generic x86_64 candidate"
[ "$(uu_wizard_mode xiaoqiang aarch64)" = migration ] || fail "XiaoQiang legacy migration route"
[ "$(uu_wizard_mode openwrt mips)" = collect ] || fail "unsupported big/generic MIPS blocked"
ok "platform routing classifies models without accepting unsupported MIPS"

for mode in official experimental collect; do
    if uu_wizard_can_setup "$mode"; then fail "unsafe mode $mode must never install"; fi
    if uu_wizard_can_rollback "$mode"; then fail "unsafe mode $mode must never rollback"; fi
done
uu_wizard_can_stage experimental || fail "MIPS read-only staging allowed"
! uu_wizard_can_stage unknown || fail "unknown should not stage"
! uu_wizard_can_stage official || fail "ASUS should use official integration"
uu_wizard_can_setup candidate || fail "candidate guarded install path"
uu_wizard_can_setup migration || fail "migration guarded install path"
ok "install, staging and rollback permissions fail closed"

preview=$(NO_COLOR=1 sh "$ROOT/uu-helper.sh" start --preview 2>&1)
rc=$?
[ "$rc" -eq 0 ] || fail "read-only preview"
printf '%s\n' "$preview" | grep -F '远程开机路由器助手' >/dev/null || fail "wizard header"
if printf '%s\n' "$preview" | LC_ALL=C grep "$(printf '\033')" >/dev/null 2>&1; then
    fail "no ANSI when preview is redirected"
fi
ok "wizard supports clean non-color read-only preview"

narrow=$(COLUMNS=40 NO_COLOR=1 sh "$ROOT/uu-helper.sh" start --preview 2>&1)
printf '%s\n' "$narrow" | grep -F 'UU 远程开机助手' >/dev/null || fail "narrow terminal must use compact header"
if printf '%s\n' "$narrow" | grep -F 'UU REMOTE  ·' >/dev/null; then
    fail "narrow terminal must avoid oversized banner"
fi
ok "narrow terminal gets compact adaptive layout"

noninteractive=$(sh "$ROOT/uu-helper.sh" start </dev/null 2>&1)
rc=$?
[ "$rc" -eq 64 ] || fail "unattended input cannot enter dangerous wizard"
printf '%s\n' "$noninteractive" | grep -F '交互终端' >/dev/null || fail "noninteractive failure must be actionable"
ok "no noninteractive wizard execution"

if command -v script >/dev/null 2>&1; then
    # CI Linux itself is not OpenWrt: unknown mode must refuse menu injection.
    session=$(printf '3\n0\n' | TERM=xterm script -q -c "sh '$ROOT/uu-helper.sh' start" /dev/null 2>&1)
    printf '%s\n' "$session" | grep -F '不允许安装' >/dev/null || fail "blocked menu option still refuses install"
    if printf '%s\n' "$session" | grep -F '分步测试与安装（需人工确认）' >/dev/null; then
        fail "unknown host must not render unsafe installer menu"
    fi
    ok "real pseudo-terminal unknown-host menu refuses forced install"
else
    echo "ok - optional PTY test skipped (script utility unavailable)"
fi
printf '%s\n' 'all wizard policy and presentation tests passed'
