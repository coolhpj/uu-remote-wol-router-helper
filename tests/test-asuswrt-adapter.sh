#!/bin/sh
set -u

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
TMP_ROOT="/tmp/uu-wol-helper-asus-test-$$"
BIN_DIR="$TMP_ROOT/bin"
JFFS_DIR="$TMP_ROOT/jffs"
KOOLSHARE_DIR="$TMP_ROOT/koolshare"
PERSIST_DIR="$JFFS_DIR/uu"
RUNTIME_DIR="$TMP_ROOT/runtime"

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$BIN_DIR" "$PERSIST_DIR" "$KOOLSHARE_DIR" "$RUNTIME_DIR"

cat > "$BIN_DIR/nvram" <<'EOF'
#!/bin/sh
[ "$1" = "get" ] || exit 1
case "$2" in
    productid) printf '%s\n' "${FAKE_ASUS_MODEL:-RT-AX86U}" ;;
    buildno) printf '%s\n' "388" ;;
    extendno) printf '%s\n' "388.11-test" ;;
    sw_mode) printf '%s\n' "1" ;;
    *) printf '\n' ;;
esac
EOF
chmod +x "$BIN_DIR/nvram"

cat > "$BIN_DIR/ps" <<'EOF'
#!/bin/sh
cat <<'OUT'
100 root 100 S /bin/sh /jffs/uu/uuplugin_monitor.sh
101 root 100 S /tmp/uu/uuplugin /tmp/uu/uu.conf
102 root 100 S xuplugin-guardian 6
103 root 100 S /koolshare/bin/clash -d /koolshare/merlinclash/
OUT
EOF
chmod +x "$BIN_DIR/ps"

cat > "$BIN_DIR/netstat" <<'EOF'
#!/bin/sh
printf '%s\n' 'tcp 0 0 local:40000 remote:16000 ESTABLISHED 101/uuplugin'
EOF
chmod +x "$BIN_DIR/netstat"

cat > "$RUNTIME_DIR/uu.conf" <<'EOF'
log_level=info
version=v99.1-test
EOF

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

common_env="PATH=$BIN_DIR:$PATH UU_ASUS_JFFS_DIR=$JFFS_DIR UU_ASUS_KOOLSHARE_DIR=$KOOLSHARE_DIR UU_ASUS_PERSIST_DIR=$PERSIST_DIR UU_ASUS_RUNTIME_DIR=$RUNTIME_DIR"

detect_output=$(env $common_env sh "$ROOT_DIR/platforms/asuswrt/detect.sh") || {
    echo "not ok - ASUSWRT detector should match fake RT-AX86U" >&2
    exit 1
}
assert_contains "$detect_output" "matched: yes" "detect ASUSWRT platform"
assert_contains "$detect_output" "model: RT-AX86U" "report ASUS model"
assert_contains "$detect_output" "koolshare: present" "report KoolShare reference environment"

health_output=$(env $common_env sh "$ROOT_DIR/platforms/asuswrt/health.sh") || {
    echo "not ok - ASUSWRT health should pass fake healthy runtime" >&2
    exit 1
}
assert_contains "$health_output" "version: v99.1-test" "read runtime version"
assert_contains "$health_output" "monitor: online" "detect monitor"
assert_contains "$health_output" "uuplugin: online" "detect uuplugin"
assert_contains "$health_output" "guardian: online" "detect guardian"
assert_contains "$health_output" "cloud_16000: online" "detect UU cloud connection"
assert_contains "$health_output" "mc2_clash_reference: online" "detect MC2 coexistence reference"

helper_output=$(env $common_env sh "$ROOT_DIR/uu-helper.sh" diagnose) || {
    echo "not ok - helper diagnose should use ASUSWRT adapter in fake ASUS environment" >&2
    exit 1
}
assert_contains "$helper_output" "platform: asuswrt" "helper selects ASUSWRT adapter"
assert_contains "$helper_output" "health_summary: healthy" "helper reports healthy ASUSWRT runtime"

if env FAKE_ASUS_MODEL=SomeOtherRouter $common_env sh "$ROOT_DIR/platforms/asuswrt/detect.sh" >/dev/null 2>&1; then
    echo "not ok - non-ASUS model should not match ASUSWRT adapter" >&2
    exit 1
fi
printf 'ok - reject unrelated nvram platform\n'

printf 'all ASUSWRT adapter tests passed\n'
