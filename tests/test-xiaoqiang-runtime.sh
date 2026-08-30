#!/bin/sh
set -u

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
TMP_ROOT="/tmp/uu-wol-helper-xq-runtime-test-$$"
BIN_DIR="$TMP_ROOT/bin"
PLUGIN_DIR="$TMP_ROOT/plugin"
STATE_DIR="$TMP_ROOT/state"
LOG="$TMP_ROOT/boot.log"

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$BIN_DIR" "$PLUGIN_DIR" "$STATE_DIR"

assert_contains() {
    haystack="$1"
    needle="$2"
    label="$3"
    if printf '%s\n' "$haystack" | grep -F "$needle" >/dev/null 2>&1; then
        printf 'ok - %s\n' "$label"
    else
        printf 'not ok - %s\n' "$label" >&2
        exit 1
    fi
}

# --- xnetease-uu AP-mode guard ---
cat > "$BIN_DIR/uci" <<'EOF'
#!/bin/sh
printf '%s\n' "${FAKE_NETMODE:-wifiapmode}"
EOF
chmod +x "$BIN_DIR/uci"

for name in killall sleep; do
    cat > "$BIN_DIR/$name" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$BIN_DIR/$name"
done

cat > "$PLUGIN_DIR/uuplugin_monitor.sh" <<'EOF'
#!/bin/sh
printf '%s\n' started > "${FAKE_MONITOR_MARKER:?}"
EOF
chmod +x "$PLUGIN_DIR/uuplugin_monitor.sh"

ap_output=$(PATH="$BIN_DIR:$PATH" UU_PLUGIN_DIR="$PLUGIN_DIR" FAKE_NETMODE=wifiapmode FAKE_MONITOR_MARKER="$STATE_DIR/monitor" sh "$ROOT_DIR/platforms/xiaoqiang/runtime/xnetease-uu" plugon)
assert_contains "$ap_output" "In AP mode, exit!" "reject XiaoQiang AP mode"
[ ! -e "$STATE_DIR/monitor" ] || {
    echo "not ok - AP mode must not start monitor" >&2
    exit 1
}
printf 'ok - AP mode leaves monitor stopped\n'

PATH="$BIN_DIR:$PATH" UU_PLUGIN_DIR="$PLUGIN_DIR" FAKE_NETMODE=whc_cap FAKE_MONITOR_MARKER="$STATE_DIR/monitor" sh "$ROOT_DIR/platforms/xiaoqiang/runtime/xnetease-uu" plugon
# monitor is backgrounded; give the shell a moment to run the fixture.
sleep 1
[ -f "$STATE_DIR/monitor" ] || {
    echo "not ok - router mode should start monitor" >&2
    exit 1
}
printf 'ok - router mode starts monitor\n'
rm -f "$STATE_DIR/monitor"

# --- auto.sh cloud retry behavior ---
cat > "$BIN_DIR/ip" <<'EOF'
#!/bin/sh
[ "${1:-}" = "route" ] && printf '%s\n' 'default via test-gateway dev test0'
EOF
chmod +x "$BIN_DIR/ip"

cat > "$BIN_DIR/curl" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$BIN_DIR/curl"

cat > "$BIN_DIR/netstat" <<'EOF'
#!/bin/sh
if [ -f "${FAKE_CLOUD_ONLINE:?}" ]; then
    printf '%s\n' 'tcp 0 0 local:40000 remote:16000 ESTABLISHED 100/uuplugin'
fi
EOF
chmod +x "$BIN_DIR/netstat"

cat > "$PLUGIN_DIR/xnetease-uu" <<'EOF'
#!/bin/sh
state_dir="${FAKE_STATE_DIR:?}"
case "${1:-}" in
    plugon)
        count=0
        [ -f "$state_dir/count" ] && count=$(cat "$state_dir/count")
        count=$((count + 1))
        printf '%s\n' "$count" > "$state_dir/count"
        printf 'plugon\n' >> "$state_dir/calls"
        [ "$count" -ge 2 ] && : > "$state_dir/online"
        ;;
    plugoff)
        printf 'plugoff\n' >> "$state_dir/calls"
        rm -f "$state_dir/online"
        ;;
esac
EOF
chmod +x "$PLUGIN_DIR/xnetease-uu"

rm -f "$STATE_DIR/count" "$STATE_DIR/calls" "$STATE_DIR/online" "$LOG"
PATH="$BIN_DIR:$PATH" \
UU_PLUGIN_DIR="$PLUGIN_DIR" \
UU_BOOT_LOG="$LOG" \
UU_API_URL='https://example.invalid/api' \
FAKE_STATE_DIR="$STATE_DIR" \
FAKE_CLOUD_ONLINE="$STATE_DIR/online" \
sh "$ROOT_DIR/platforms/xiaoqiang/runtime/auto.sh"

# All sleeps inside auto.sh are fixture no-ops, so one second is ample.
sleep 1

calls=$(cat "$STATE_DIR/calls" 2>/dev/null || true)
assert_contains "$calls" "plugoff" "retry path performs plugoff"
plugon_count=$(grep -c '^plugon$' "$STATE_DIR/calls" 2>/dev/null || true)
[ "$plugon_count" -eq 2 ] || {
    echo "not ok - retry path should perform exactly two plugon calls" >&2
    exit 1
}
printf 'ok - retry path performs two plugon attempts\n'

boot_log=$(cat "$LOG" 2>/dev/null || true)
assert_contains "$boot_log" "network ready" "boot helper waits for network readiness"
assert_contains "$boot_log" "first cloud connect failed, retry" "boot helper detects first cloud failure"
assert_contains "$boot_log" "UU cloud online" "boot helper records final cloud success"

printf 'all XiaoQiang runtime tests passed\n'
