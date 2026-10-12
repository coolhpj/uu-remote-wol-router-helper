#!/bin/sh
# Host-only boot loader test: no official network call, no real UU binary.
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd) || exit 1
BOOT="$ROOT/platforms/openwrt/runtime/mips-experimental-boot.sh"
fail() { echo "not ok - $*" >&2; exit 1; }
base="/tmp/uu-wol-helper-boot-test-$$"
stage="/tmp/uu-wol-helper-boot-stage-$$"
mkdir -p "$base/app/lib" "$base/app/scripts" "$base/bin" "$stage"
trap 'rm -rf "$base" "$stage"' EXIT HUP INT TERM
printf 'managed_by=uu-remote-wol-router-helper-mips-beta\n' > "$base/app/install.meta"
cat > "$base/app/lib/channel.sh" <<'EOF'
uu_openwrt_detect_arch() { printf 'mipsel_24kc\n'; }
EOF
cat > "$base/app/lib/elf.sh" <<'EOF'
uu_check_stage_mipsel_elf() { [ -f "$1/files/uuplugin" ]; }
EOF
cat > "$base/app/scripts/stage-package.sh" <<'EOF'
#!/bin/sh
[ "$1" = "openwrt-mipsel" ] || exit 3
[ "${MOCK_STAGE_FAIL:-no}" = no ] || exit 4
mkdir -p "$UU_STAGE_DIR/files"
printf 'channel=openwrt-mipsel\n' > "$UU_STAGE_DIR/metadata"
cat > "$UU_STAGE_DIR/files/uuplugin" <<'INNER'
#!/bin/sh
printf 'MOCK_BOOT_PLUGIN_CALLED\n'
exit 0
INNER
chmod +x "$UU_STAGE_DIR/files/uuplugin"
EOF
cat > "$base/bin/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$base/bin/sleep" "$base/app/scripts/stage-package.sh"
out=$(UU_TEST_MODE=1 UU_MIPS_APP_DIR="$base/app" UU_MIPS_STAGE_DIR="$stage" PATH="$base/bin:$PATH" sh "$BOOT" 2>&1)
rc=$?
[ "$rc" -eq 0 ] || fail "boot returned $rc: $out"
printf "%s\n" "$out" | grep -q MOCK_BOOT_PLUGIN_CALLED || fail "no plugin exec after staged verification"
echo "ok - boot staging, verification and exec path"
out=$(UU_TEST_MODE=1 UU_MIPS_APP_DIR="$base/app" UU_MIPS_STAGE_DIR="$stage" MOCK_STAGE_FAIL=yes PATH="$base/bin:$PATH" sh "$BOOT" 2>&1)
rc=$?
[ "$rc" -eq 69 ] || fail "failed download must never start plugin"
! printf "%s\n" "$out" | grep -q MOCK_BOOT_PLUGIN_CALLED || fail "plugin started after failed stage"
echo "ok - failed official package download blocks boot"
echo "all MIPS beta boot tests passed"
