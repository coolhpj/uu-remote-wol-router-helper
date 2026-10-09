#!/bin/sh
set -u

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/lib/channel.sh"

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

assert_eq() {
    expected="$1"
    actual="$2"
    label="$3"
    [ "$expected" = "$actual" ] || fail "$label (expected=$expected actual=$actual)"
    printf 'ok - %s\n' "$label"
}

assert_eq openwrt-aarch64 "$(uu_openwrt_channel_for_arch aarch64)" "map aarch64 OpenWrt channel"
assert_eq openwrt-aarch64 "$(uu_openwrt_channel_for_arch arm64)" "map arm64 alias"
assert_eq openwrt-x86_64 "$(uu_openwrt_channel_for_arch x86_64)" "map x86_64 OpenWrt channel"
assert_eq openwrt-x86_64 "$(uu_openwrt_channel_for_arch amd64)" "map amd64 alias"
assert_eq openwrt-mipsel "$(uu_openwrt_channel_for_arch mipsel_24kc)" "map verified MIPS little-endian package architecture"
assert_eq openwrt-mipsel "$(uu_resolve_channel openwrt mipsel_24kc)" "resolve Generic OpenWrt MIPS little-endian channel"
assert_eq openwrt-x86_64 "$(uu_resolve_channel openwrt x86_64)" "resolve Generic OpenWrt channel"
assert_eq openwrt-aarch64 "$(uu_resolve_channel xiaoqiang aarch64)" "resolve XiaoQiang channel"

for unsupported in mips mipsel mipseb mipsel_24kec mips_24kc mips64; do
    if uu_openwrt_channel_for_arch "$unsupported" >/dev/null 2>&1; then
        fail "architecture $unsupported must fail closed"
    fi
done
printf 'ok - generic/other MIPS architectures fail closed\n'

if UU_ARCH_OVERRIDE=mipsel_24kc uu_openwrt_detect_arch >/dev/null 2>&1; then
    fail "MIPS architecture override must fail closed"
fi
printf 'ok - MIPS environment override cannot bypass metadata validation\n'

# Emulate the exact Lenovo Y1 OpenWrt report without requiring real hardware.
FIXTURE=$(mktemp -d /tmp/uu-wol-helper-mips-test.XXXXXX) || exit 1
trap 'rm -rf "$FIXTURE"' EXIT HUP INT TERM
mkdir -p "$FIXTURE/bin"
cat > "$FIXTURE/bin/uname" <<'EOF'
#!/bin/sh
printf 'mips\n'
EOF
cat > "$FIXTURE/bin/opkg" <<'EOF'
#!/bin/sh
printf 'arch all 1\narch noarch 1\narch %s 10\n' "${UU_TEST_OPKG_ARCH:-mipsel_24kc}"
EOF
chmod +x "$FIXTURE/bin/uname" "$FIXTURE/bin/opkg"
cat > "$FIXTURE/openwrt_release" <<'EOF'
DISTRIB_ID='OpenWrt'
DISTRIB_RELEASE='22.03-SNAPSHOT'
DISTRIB_TARGET='ramips/mt7620'
DISTRIB_ARCH='mipsel_24kc'
EOF

actual=$(PATH="$FIXTURE/bin:$PATH" UU_OPENWRT_RELEASE_FILE="$FIXTURE/openwrt_release" uu_openwrt_detect_arch)
assert_eq mipsel_24kc "$actual" "Lenovo Y1 release and opkg independently confirm little-endian MIPS"

preflight=$(PATH="$FIXTURE/bin:$PATH" UU_OPENWRT_RELEASE_FILE="$FIXTURE/openwrt_release" sh "$ROOT_DIR/platforms/openwrt/preflight.sh") || fail "Lenovo Y1 preflight must pass simulated environment"
printf '%s\n' "$preflight" | grep -F 'channel: openwrt-mipsel' >/dev/null 2>&1 || fail "Lenovo Y1 preflight picks wrong channel"
printf 'ok - Lenovo Y1 simulated preflight selects official mipsel channel\n'

if PATH="$FIXTURE/bin:$PATH" UU_OPENWRT_RELEASE_FILE="$FIXTURE/openwrt_release" UU_TEST_OPKG_ARCH=mipseb_24kc uu_openwrt_detect_arch >/dev/null 2>&1; then
    fail "MIPS mismatched opkg architecture must fail closed"
fi
printf 'ok - mismatched opkg MIPS architecture fails closed\n'

sed "s/mipsel_24kc/mipseb_24kc/g" "$FIXTURE/openwrt_release" > "$FIXTURE/bad_release"
if PATH="$FIXTURE/bin:$PATH" UU_OPENWRT_RELEASE_FILE="$FIXTURE/bad_release" uu_openwrt_detect_arch >/dev/null 2>&1; then
    fail "MIPS big-endian release must fail closed"
fi
printf 'ok - big-endian MIPS release fails closed\n'

uu_resolve_channel asuswrt aarch64 >/dev/null 2>&1
asus_rc=$?
[ "$asus_rc" -eq 2 ] || fail "ASUSWRT must return model-specific status"
printf 'ok - ASUSWRT auto staging is intentionally disabled\n'

printf 'all channel mapping tests passed\n'
