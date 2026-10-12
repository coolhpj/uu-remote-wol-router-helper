#!/bin/sh
# Host-only Lenovo Y1 persistent bootstrap packaging safety tests.
set -u
ROOT=$(CDPATH= cd "$(dirname "$0")/.." && pwd) || exit 1
INSTALL="$ROOT/platforms/openwrt/mips-experimental-install.sh"
UNINSTALL="$ROOT/platforms/openwrt/mips-experimental-uninstall.sh"
BOOT="$ROOT/platforms/openwrt/runtime/mips-experimental-boot.sh"
STOP="$ROOT/platforms/openwrt/runtime/mips-experimental-stop.sh"
fail() { echo "not ok - $*" >&2; exit 1; }
ok() { echo "ok - $*"; }

base="/tmp/uu-wol-helper-beta-test-$$"
stage="/tmp/uu-wol-helper-stage-beta-test-$$"
root="/tmp/uu-wol-helper-root-beta-test-$$"
mkdir -p "$base/bin" "$stage/files" "$root"
trap 'rm -rf "$base" "$stage" "$root"' EXIT HUP INT TERM
cat > "$base/bin/uname" <<'EOF'
#!/bin/sh
printf 'mips\n'
EOF
cat > "$base/bin/opkg" <<'EOF'
#!/bin/sh
printf 'arch all 1\narch mipsel_24kc 10\n'
EOF
chmod +x "$base/bin/uname" "$base/bin/opkg"
cat > "$base/release" <<'EOF'
DISTRIB_ARCH='mipsel_24kc'
DISTRIB_TARGET='ramips/mt7620'
EOF

# Correct MIPS32r2 ELF headers - never executed on this host.
printf '\177ELF\001\001\001\000\000\000\000\000\000\000\000\000\002\000\010\000\001\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\005\020\000\160' > "$stage/files/uuplugin"
for f in xuplugin-guardian xtables-nft-multi; do
    cp "$stage/files/uuplugin" "$stage/files/$f"
done
printf 'version=fixture\n' > "$stage/files/uu.conf"
tar -czf "$stage/uu.tar.gz" -C "$stage/files" uuplugin xuplugin-guardian xtables-nft-multi uu.conf
md5=$(md5sum "$stage/uu.tar.gz")
printf 'channel=openwrt-mipsel\nmd5=%s\n' "${md5%% *}" > "$stage/metadata"
common="UU_TEST_MODE=1 UU_TARGET_ROOT=$root UU_STAGE_DIR=$stage UU_OPENWRT_RELEASE_FILE=$base/release"
env PATH="$base/bin:$PATH" $common sh "$INSTALL" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 64 ] || fail "beta install needs explicit opt-in"
ok "beta install default denied"

out=$(env PATH="$base/bin:$PATH" $common UU_TEST_MODEL="Some other MT7620 router" UU_MIPS_BETA_INSTALL_CONFIRM=I_ACCEPT_LENOVO_Y1_EXPERIMENTAL_PERSISTENCE sh "$INSTALL" 2>&1)
rc=$?
[ "$rc" -eq 67 ] || fail "unapproved model must be blocked"
ok "generic MIPS device cannot use Lenovo Y1 beta"

out=$(env PATH="$base/bin:$PATH" $common UU_TEST_MODEL="Lenovo Y1" UU_MIPS_BETA_INSTALL_CONFIRM=I_ACCEPT_LENOVO_Y1_EXPERIMENTAL_PERSISTENCE sh "$INSTALL" 2>&1)
rc=$?
[ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q 'MIPS_BETA_INSTALL_FILES_READY' || fail "install fixture: $out"
app="$root/usr/lib/uu-mips-wol-helper"
init="$root/etc/init.d/uu-mips-wol-helper"
[ -f "$app/install.meta" ] && [ -f "$app/boot.sh" ] && [ -f "$app/stop.sh" ] &&
[ -f "$app/scripts/stage-package.sh" ] && [ -f "$app/lib/elf.sh" ] &&
[ -f "$init" ] || fail "required files missing"
[ ! -e "$app/uuplugin" ] && [ ! -e "$app/xtables-nft-multi" ] || fail "closed binaries not copied to flash"
grep -q 'managed_by=uu-remote-wol-router-helper-mips-beta' "$app/install.meta" || fail "owner marker"
grep -q 'procd_set_param' "$init" || fail "must use procd"
! grep -q 'killall' "$STOP" || fail "must never kill unrelated UU processes by name"
! grep -q 'flush ruleset' "$STOP" || fail "must not flush entire firewall"
ok "dedicated beta files only, no plugin binaries or global process termination"

out=$(env PATH="$base/bin:$PATH" $common UU_TEST_MODEL="Lenovo Y1" UU_MIPS_BETA_INSTALL_CONFIRM=I_ACCEPT_LENOVO_Y1_EXPERIMENTAL_PERSISTENCE sh "$INSTALL" 2>&1)
rc=$?
[ "$rc" -eq 65 ] || fail "second install must not overwrite the first"
ok "existing installation is never overwritten"

out=$(env $common UU_MIPS_BETA_UNINSTALL_CONFIRM=REMOVE_LENOVO_Y1_BETA_SERVICE sh "$UNINSTALL" 2>&1)
rc=$?
[ "$rc" -eq 0 ] && [ ! -e "$app" ] && [ ! -e "$init" ] || fail "uninstall fixture $out"
ok "dedicated uninstall only removes managed beta files"

out=$(env $common UU_MIPS_BETA_UNINSTALL_CONFIRM=REMOVE_LENOVO_Y1_BETA_SERVICE sh "$UNINSTALL" 2>&1)
rc=$?
[ "$rc" -eq 4 ] || fail "uninstall refuses unowned paths"
ok "nonexistent/unowned installation fails closed"

# A corrupted official archive must never grant persistence eligibility.
printf 'changed\n' >> "$stage/uu.tar.gz"
out=$(env PATH="$base/bin:$PATH" $common UU_TEST_MODEL="Lenovo Y1" UU_MIPS_BETA_INSTALL_CONFIRM=I_ACCEPT_LENOVO_Y1_EXPERIMENTAL_PERSISTENCE sh "$INSTALL" 2>&1)
rc=$?
[ "$rc" -eq 4 ] && [ ! -e "$app" ] || fail "bad official checksum must fail before writing"
ok "corrupted package refuses beta install"

sh -n "$BOOT" && sh -n "$STOP" || fail "runtime script syntax"
echo "all MIPS beta packaging safety tests passed"
