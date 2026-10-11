#!/bin/sh
# Pure host mocks: no router plugin, real network changes or iptables changes.
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd) || exit 1
RUNNER="$ROOT/platforms/openwrt/mips-runtime-smoke.sh"
STOP="$ROOT/platforms/openwrt/mips-runtime-stop.sh"
WATCHDOG="$ROOT/platforms/openwrt/mips-runtime-watchdog.sh"
fail() { echo "not ok - $*" >&2; exit 1; }
ok() { echo "ok - $*"; }

BASE="/tmp/uu-wol-helper-mips-flow-$$"
mkdir -p "$BASE/bin" "$BASE/files"
trap 'rm -rf "$BASE"' EXIT HUP INT TERM
export UU_TEST_NFT_STATE="$BASE/nft.state"
export UU_TEST_NFT_BASE="$BASE/nft.initial"
export UU_TEST_FW4_COUNT="$BASE/fw4.calls"
printf 'table inet fw4 { chain input { type filter hook input priority filter; policy accept; } }\n' > "$UU_TEST_NFT_BASE"
cp "$UU_TEST_NFT_BASE" "$UU_TEST_NFT_STATE"
cat > "$BASE/bin/nft" <<'EOF'
#!/bin/sh
if [ "$1" = "-s" ] && [ "$2" = "list" ] && [ "$3" = "ruleset" ]; then
    cat "$UU_TEST_NFT_STATE"
elif [ "$1" = "list" ] && [ "$2" = "tables" ]; then
    echo 'table inet fw4'
else
    exit 1
fi
EOF
cat > "$BASE/bin/fw4" <<'EOF'
#!/bin/sh
[ "$1" = "reload" ] || exit 2
echo reload >> "$UU_TEST_FW4_COUNT"
[ "${UU_TEST_FW4_FAIL:-no}" != yes ] || exit 1
cp "$UU_TEST_NFT_BASE" "$UU_TEST_NFT_STATE"
EOF
chmod +x "$BASE/bin/nft" "$BASE/bin/fw4"
export PATH="$BASE/bin:$PATH"

create_run() {
    run="$BASE/mips-smoke-run-$1"
    mkdir -p "$run"
    echo 99999999 > "$run/owner"
    cp "$UU_TEST_NFT_BASE" "$run/firewall.before"
}
create_run 1
out=$(sh "$STOP" "$BASE" "$run" 2>&1)
rc=$?
[ "$rc" -eq 0 ] && [ -f "$run/done" ] || fail "unchanged firewall and no staged processes should clean"
printf '%s\n' "$out" | grep -F 'firewall_restore: unchanged' >/dev/null || fail "baseline must not reload fw4"
[ ! -e "$UU_TEST_FW4_COUNT" ] || fail "fw4 must not reload when unchanged"
ok "unchanged nft ruleset no-op cleanup"

create_run 2
echo 'table ip XU_TEST { chain xx { } }' >> "$UU_TEST_NFT_STATE"
out=$(sh "$STOP" "$BASE" "$run" 2>&1)
rc=$?
[ "$rc" -eq 0 ] && [ -f "$run/done" ] || fail "firewall recovery failed"
[ "$(wc -l < "$UU_TEST_FW4_COUNT")" -eq 1 ] || fail "fw4 expected exactly one reload"
cmp -s "$UU_TEST_NFT_BASE" "$UU_TEST_NFT_STATE" || fail "fw4 must restore original ruleset"
ok "changed firewall triggers a single verified fw4 reload"

create_run 3
echo 'table ip XU_TEST { chain xx { } }' >> "$UU_TEST_NFT_STATE"
out=$(UU_TEST_FW4_FAIL=yes sh "$STOP" "$BASE" "$run" 2>&1)
rc=$?
[ "$rc" -eq 8 ] && [ -f "$run/cleanup.incomplete" ] && [ ! -f "$run/done" ] || fail "failed firewall restore must be incomplete"
printf '%s\n' "$out" | grep -F 'CLEANUP_INCOMPLETE' >/dev/null || fail "failure must be visible"
ok "firewall restore failure fails closed"

# Prove independent watchdog triggers cleanup after parent is dead, without
# relying on an SSH shell trap, and cannot touch anything outside stage.
cp "$UU_TEST_NFT_BASE" "$UU_TEST_NFT_STATE"
create_run 4
sh "$WATCHDOG" "$BASE" "$run" 60
[ -f "$run/done" ] || fail "watchdog must perform recovery when owner vanished"
ok "orphaned owner triggers watchdog cleanup"

# Simulate an SSH hangup with a real detached /bin/sh child, not nohup.
# The child must live long enough to clean up after its parent gets SIGHUP.
cat > "$BASE/hup-launcher.sh" <<'EOF'
#!/bin/sh
stage="$1"; run="$2"; watchdog="$3"
printf '%s\n' "$$" > "$run/owner"
(
    trap '' HUP
    exec sh "$watchdog" "$stage" "$run" 60
) </dev/null >>"$run/watchdog.log" 2>&1 &
echo "$!" > "$run/watchdog.pid"
while :; do sleep 1; done
EOF
create_run 7
sh "$BASE/hup-launcher.sh" "$BASE" "$run" "$WATCHDOG" &
launcher_pid=$!
retries=0
while [ ! -f "$run/watchdog.ready" ] && [ "$retries" -lt 10 ]; do
    sleep 1
    retries=$((retries + 1))
done
if [ ! -f "$run/watchdog.ready" ]; then
    kill "$launcher_pid" 2>/dev/null || true
    fail "detached watchdog never signalled ready"
fi
watchdog_pid=$(cat "$run/watchdog.pid")
kill -0 "$watchdog_pid" 2>/dev/null || fail "watchdog not alive before hangup"
kill -HUP "$launcher_pid" 2>/dev/null || fail "failed to deliver hangup"
wait "$launcher_pid" 2>/dev/null || true
retries=0
while [ ! -f "$run/done" ] && [ "$retries" -lt 10 ]; do
    sleep 1
    retries=$((retries + 1))
done
[ -f "$run/done" ] || fail "watchdog did not survive HUP and recover"
printf '%s\n' "$(cat "$run/watchdog.log")" | grep -F 'owner_exited: auto_cleanup' >/dev/null || fail "watchdog must observe owner disconnect"
ok "POSIX shell watcher survives SSH-style SIGHUP without nohup"

# Confirm exact /proc executable ownership: a staged binary is stopped,
# unrelated process survives. This uses a host sleep COPY, never UU binaries.
cp "$(command -v sleep)" "$BASE/files/uuplugin" || fail "copy host sleep fixture"
"$BASE/files/uuplugin" 60 &
owned_pid=$!
sleep 1
sleep 60 &
unrelated_pid=$!
create_run 5
sh "$STOP" "$BASE" "$run" >/dev/null 2>&1 || fail "PID-scoped cleanup failed"
[ -z "$(readlink "/proc/$owned_pid/exe" 2>/dev/null || true)" ] || fail "owned staged process not terminated"
kill -0 "$unrelated_pid" 2>/dev/null || fail "unrelated sleep must survive"
kill "$unrelated_pid" 2>/dev/null || true
wait "$unrelated_pid" 2>/dev/null || true
wait "$owned_pid" 2>/dev/null || true
ok "PID-scoped cleanup stops staged process only"

mkdir -p "$BASE/rogue"
cp "$(command -v sleep)" "$BASE/rogue/uuplugin"
"$BASE/rogue/uuplugin" 60 &
rogue_pid=$!
sleep 1
create_run 6
out=$(sh "$STOP" "$BASE" "$run" 2>&1)
rc=$?
[ "$rc" -eq 8 ] && [ -f "$run/cleanup.incomplete" ] || fail "unowned UU process must prevent successful cleanup"
kill -0 "$rogue_pid" 2>/dev/null || fail "unowned process must not be killed"
kill "$rogue_pid" 2>/dev/null || true
wait "$rogue_pid" 2>/dev/null || true
ok "unknown UU child is not killed, cleanup fails closed"

# Required user acknowledgement precedes every environmental check.
out=$(sh "$RUNNER" 2>&1)
rc=$?
[ "$rc" -eq 64 ] || fail "MIPS experimental runner must default to disabled"
printf '%s\n' "$out" | grep -F 'disabled by default' >/dev/null || fail "missing refusal"
ok "MIPS runtime disabled without explicit confirmation"

cat > "$BASE/bin/uname" <<'EOF'
#!/bin/sh
echo mips
EOF
cat > "$BASE/bin/opkg" <<'EOF'
#!/bin/sh
echo 'arch all 1'
echo 'arch mipsel_24kc 10'
EOF
cat > "$BASE/bin/netstat" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$BASE/bin/id" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "-u" ]; then
    echo 0
else
    /usr/bin/id "$@"
fi
EOF
chmod +x "$BASE/bin/uname" "$BASE/bin/opkg" "$BASE/bin/netstat" "$BASE/bin/id"
cat > "$BASE/release" <<'EOF'
DISTRIB_ID='OpenWrt'
DISTRIB_ARCH='mipsel_24kc'
DISTRIB_RELEASE='22.03-SNAPSHOT'
DISTRIB_TARGET='ramips/mt7620'
EOF
# Even with confirmation, MIPS runner must refuse a non-staged payload.
out=$(UU_OPENWRT_RELEASE_FILE="$BASE/release" UU_MIPS_RUNTIME_CONFIRM=ONE_TIME_MIPS_TEST_WITH_LOCAL_RECOVERY UU_STAGE_DIR="/tmp/uu-wol-helper-mips-absent-$$" sh "$RUNNER" 2>&1)
rc=$?
[ "$rc" -eq 4 ] || fail "missing stage must fail with code 4, actual $rc: $out"
[ ! -d "/tmp/uu-wol-helper-mips-absent-$$" ] || fail "runner cannot invent stage"
ok "MIPS runner refuses absent stage before launching processes"

mkdir "$BASE/mips-smoke.lock" || fail "create active test lock"
out=$(UU_STAGE_DIR="$BASE" sh "$ROOT/scripts/stage-package.sh" openwrt-mipsel 2>&1)
rc=$?
[ "$rc" -eq 65 ] || fail "re-stage during incomplete test must be blocked before API request"
printf '%s\n' "$out" | grep -F 'refuse to re-stage' >/dev/null 2>&1 || fail "restage lock error should be actionable"
[ -f "$BASE/mips-smoke-run-3/cleanup.incomplete" ] || fail "re-stage must preserve failed recovery evidence"
rmdir "$BASE/mips-smoke.lock" || fail "remove fixture lock"
ok "re-stage refuses to overwrite active or incomplete cleanup state"

for file in "$RUNNER" "$STOP" "$WATCHDOG"; do
    ! grep -v '^[[:space:]]*#' "$file" | grep -Eq 'killall|flush ruleset|iptables -F' || fail "unsafe global kill/flush in $file"
done
ok "new runner contains no killall or global firewall flush"
echo "all MIPS single-session lifecycle tests passed"
