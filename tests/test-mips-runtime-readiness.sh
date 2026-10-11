#!/bin/sh
set -u

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
SMOKE="$ROOT_DIR/platforms/openwrt/smoke-test.sh"
READINESS="$ROOT_DIR/platforms/openwrt/mips-runtime-readiness.sh"
fail() { echo "not ok - $1" >&2; exit 1; }
ok() { echo "ok - $1"; }

FIXTURE=$(mktemp -d /tmp/uu-wol-helper-mips-readiness-test.XXXXXX) || exit 1
trap 'rm -rf "$FIXTURE"' 0 HUP INT TERM
mkdir -p "$FIXTURE/bin"

cat > "$FIXTURE/bin/uname" <<'EOF'
#!/bin/sh
printf 'mips\n'
EOF
cat > "$FIXTURE/bin/opkg" <<'EOF'
#!/bin/sh
printf 'arch all 1\narch noarch 1\narch mipsel_24kc 10\n'
EOF
chmod +x "$FIXTURE/bin/uname" "$FIXTURE/bin/opkg"
cat > "$FIXTURE/release" <<'EOF'
DISTRIB_ID='OpenWrt'
DISTRIB_ARCH='mipsel_24kc'
DISTRIB_RELEASE='22.03-SNAPSHOT'
DISTRIB_TARGET='ramips/mt7620'
EOF

# The MIPS block must execute before any package/process/firewall action,
# even if the user explicitly sets the generic runtime confirmation token.
out=$(PATH="$FIXTURE/bin:$PATH" UU_OPENWRT_RELEASE_FILE="$FIXTURE/release" UU_RUNTIME_TEST_CONFIRM=TEMPORARY_RUNTIME_CHANGE sh "$SMOKE" 2>&1)
rc=$?
[ "$rc" -eq 67 ] || fail "generic MIPS smoke must be hard-blocked with exit 67"
printf '%s\n' "$out" | grep -F "MIPS_RUNTIME_NOT_AUTHORIZED" >/dev/null 2>&1 || fail "MIPS refusal must explain why"
ok "MIPS smoke blocked even with generic confirmation"

out=$(PATH="$FIXTURE/bin:$PATH" UU_OPENWRT_RELEASE_FILE="$FIXTURE/release" UU_STAGE_DIR="/tmp/uu-wol-helper-readiness-no-files-$$" sh "$READINESS" 2>&1)
rc=$?
[ "$rc" -eq 0 ] || fail "readiness inventory failed unexpectedly"
printf '%s\n' "$out" | grep -F 'mode: read-only' >/dev/null 2>&1 || fail "readiness must declare read-only"
printf '%s\n' "$out" | grep -F 'stage_check: missing_or_invalid' >/dev/null 2>&1 || fail "readiness must report missing package honestly"
printf '%s\n' "$out" | grep -F 'runtime_test: blocked_pending_safety_review' >/dev/null 2>&1 || fail "readiness must not grant runtime permission"
printf '%s\n' "$out" | grep -F 'result: inventory_only' >/dev/null 2>&1 || fail "readiness must remain inventory only"
[ ! -e "/tmp/uu-wol-helper-readiness-no-files-$$" ] || fail "readiness must not create stage dir"
ok "read-only MIPS diagnostic reports missing stage without writing"

# Synthetic, non-executable MIPS32r2 files and archive: verify that an actual
# matching stage is reported accurately without running any copied binary.
mkdir -p "$FIXTURE/files"
printf '\177ELF\001\001\001\000\000\000\000\000\000\000\000\000\002\000\010\000\001\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\005\020\000\160' > "$FIXTURE/good-elf"
for name in uuplugin xuplugin-guardian xtables-nft-multi; do
    cp "$FIXTURE/good-elf" "$FIXTURE/files/$name"
done
printf 'version=fixture\n' > "$FIXTURE/files/uu.conf"
tar -czf "$FIXTURE/uu.tar.gz" -C "$FIXTURE/files" uuplugin xuplugin-guardian uu.conf xtables-nft-multi
archive_md5=$(md5sum "$FIXTURE/uu.tar.gz")
archive_md5=${archive_md5%% *}
printf 'channel=openwrt-mipsel\nmd5=%s\n' "$archive_md5" > "$FIXTURE/metadata"
out=$(PATH="$FIXTURE/bin:$PATH" UU_OPENWRT_RELEASE_FILE="$FIXTURE/release" UU_STAGE_DIR="$FIXTURE" sh "$READINESS" 2>&1)
rc=$?
[ "$rc" -eq 0 ] || fail "readiness valid stage returned failure"
printf '%s\n' "$out" | grep -F 'stage_check: verified' >/dev/null 2>&1 || fail "valid MIPS stage not recognized"
printf '%s\n' "$out" | grep -F 'runtime_test: blocked_pending_safety_review' >/dev/null 2>&1 || fail "validated stage must not authorize runtime"
ok "complete synthetic MIPS stage is verified, runtime still forbidden"

cp "$FIXTURE/files/xuplugin-guardian" "$FIXTURE/saved-guardian"
printf '\002' | dd of="$FIXTURE/files/xuplugin-guardian" bs=1 seek=5 conv=notrunc 2>/dev/null
out=$(PATH="$FIXTURE/bin:$PATH" UU_OPENWRT_RELEASE_FILE="$FIXTURE/release" UU_STAGE_DIR="$FIXTURE" sh "$READINESS" 2>&1)
printf '%s\n' "$out" | grep -F 'stage_check: missing_or_invalid' >/dev/null 2>&1 || fail "corrupted MIPS guardian incorrectly passed readiness"
ok "readiness rejects modified mismatched MIPS guardian"

out=$(sh "$READINESS" 2>&1)
rc=$?
[ "$rc" -eq 3 ] || fail "non-MIPS environment should be rejected"
printf '%s\n' "$out" | grep -F 'result: unsupported_arch' >/dev/null 2>&1 || fail "wrong-arch reason missing"
ok "non-MIPS environment rejected"

echo "all MIPS runtime readiness guards passed"
