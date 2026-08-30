#!/bin/sh
set -u

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
TMP_ROOT="/tmp/uu-wol-helper-openwrt-test-$$"
BIN_DIR="$TMP_ROOT/bin"
RELEASE_FILE="$TMP_ROOT/openwrt_release"
SYSINFO_DIR="$TMP_ROOT/sysinfo"
PLUGIN_DIR="$TMP_ROOT/uu"

cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$BIN_DIR" "$SYSINFO_DIR" "$PLUGIN_DIR"

cat > "$RELEASE_FILE" <<'EOF'
DISTRIB_ID='OpenWrt'
DISTRIB_RELEASE='24.10-test'
DISTRIB_TARGET='mediatek/filogic'
DISTRIB_DESCRIPTION='OpenWrt test fixture'
EOF
printf '%s\n' 'Test OpenWrt Router' > "$SYSINFO_DIR/model"
cat > "$PLUGIN_DIR/uu.conf" <<'EOF'
log_level=info
version=v99.2-test
EOF
printf 'fixture\n' > "$PLUGIN_DIR/uuplugin"

cat > "$BIN_DIR/uci" <<'EOF'
#!/bin/sh
# XiaoQiang probe must not match this generic OpenWrt fixture.
if [ "$*" = "-q get xiaoqiang.common.NETMODE" ]; then
    exit 1
fi
exit 0
EOF
chmod +x "$BIN_DIR/uci"

for name in ubus opkg nft; do
    cat > "$BIN_DIR/$name" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "$BIN_DIR/$name"
done

cat > "$BIN_DIR/ps" <<'EOF'
#!/bin/sh
cat <<'OUT'
201 root 100 S /usr/bin/uuplugin ./uu.conf
202 root 100 S xuplugin-guardian 6
OUT
EOF
chmod +x "$BIN_DIR/ps"

cat > "$BIN_DIR/netstat" <<'EOF'
#!/bin/sh
printf '%s\n' 'tcp 0 0 local:41000 remote:16000 ESTABLISHED 201/uuplugin'
EOF
chmod +x "$BIN_DIR/netstat"

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

common_env="PATH=$BIN_DIR:$PATH UU_OPENWRT_RELEASE_FILE=$RELEASE_FILE UU_OPENWRT_SYSINFO_DIR=$SYSINFO_DIR UU_OPENWRT_PLUGIN_DIR=$PLUGIN_DIR"

detect_output=$(env $common_env sh "$ROOT_DIR/platforms/openwrt/detect.sh") || {
    echo "not ok - OpenWrt detector should match fixture" >&2
    exit 1
}
assert_contains "$detect_output" "matched: yes" "detect generic OpenWrt"
assert_contains "$detect_output" "model: Test OpenWrt Router" "report OpenWrt model"
assert_contains "$detect_output" "target: mediatek/filogic" "report OpenWrt target"
assert_contains "$detect_output" "uci: yes" "detect UCI capability"

health_output=$(env $common_env sh "$ROOT_DIR/platforms/openwrt/health.sh") || {
    echo "not ok - OpenWrt health should pass healthy fixture" >&2
    exit 1
}
assert_contains "$health_output" "version: v99.2-test" "read OpenWrt UU version"
assert_contains "$health_output" "uuplugin: online" "detect OpenWrt uuplugin"
assert_contains "$health_output" "guardian: online" "detect OpenWrt guardian"
assert_contains "$health_output" "cloud_16000: online" "detect OpenWrt cloud connection"
assert_contains "$health_output" "firewall_backend: nftables" "detect firewall backend"

helper_output=$(env $common_env sh "$ROOT_DIR/uu-helper.sh" diagnose) || {
    echo "not ok - helper diagnose should select generic OpenWrt adapter" >&2
    exit 1
}
assert_contains "$helper_output" "platform: openwrt" "helper selects generic OpenWrt adapter"
assert_contains "$helper_output" "health_summary: healthy" "helper reports healthy OpenWrt runtime"

preflight_output=$(env $common_env UU_ARCH_OVERRIDE=x86_64 sh "$ROOT_DIR/uu-helper.sh" preflight) || {
    echo "not ok - helper preflight should select generic OpenWrt preflight" >&2
    exit 1
}
assert_contains "$preflight_output" "preflight: pass" "helper selects OpenWrt preflight"
assert_contains "$preflight_output" "channel: openwrt-x86_64" "preflight auto-selects x86_64 official channel"

if UU_OPENWRT_RELEASE_FILE="$TMP_ROOT/missing-release" sh "$ROOT_DIR/platforms/openwrt/detect.sh" >/dev/null 2>&1; then
    echo "not ok - missing openwrt_release should not match" >&2
    exit 1
fi
printf 'ok - reject non-OpenWrt environment\n'

printf 'all OpenWrt adapter tests passed\n'
