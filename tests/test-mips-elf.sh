#!/bin/sh
set -u

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/lib/elf.sh"

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
ok() { printf 'ok - %s\n' "$1"; }

TMP=$(mktemp -d /tmp/uu-wol-helper-mips-elf-test.XXXXXX) || exit 1
trap 'rm -rf "$TMP"' 0 HUP INT TERM
mkdir -p "$TMP/stage/files"

# Minimal 40-byte MIPS32r2 ELF header fixture (not an executable runtime).
# ELF32, little-endian, executable, EM_MIPS, EF_MIPS_ARCH_32R2.
printf '\177ELF\001\001\001\000\000\000\000\000\000\000\000\000\002\000\010\000\001\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000\005\020\000\160' > "$TMP/good"

uu_check_mipsel_24kc_elf "$TMP/good" || fail "valid MIPS32r2 little-endian header rejected"
ok "accept correct MIPS32r2 ELF header"

for name in uuplugin xuplugin-guardian xtables-nft-multi; do
    cp "$TMP/good" "$TMP/stage/files/$name"
done
uu_check_stage_mipsel_elf "$TMP/stage" || fail "valid MIPS stage rejected"
ok "accept stage with three MIPS ELF headers"

# Byte 5 = ELF data encoding; 2 means big-endian.
cp "$TMP/good" "$TMP/big"
printf '\002' | dd of="$TMP/big" bs=1 seek=5 conv=notrunc 2>/dev/null
if uu_check_mipsel_24kc_elf "$TMP/big"; then fail "big-endian ELF accepted"; fi
ok "reject big-endian ELF"

cp "$TMP/good" "$TMP/class64"
printf '\002' | dd of="$TMP/class64" bs=1 seek=4 conv=notrunc 2>/dev/null
if uu_check_mipsel_24kc_elf "$TMP/class64"; then fail "ELF64 accepted"; fi
ok "reject ELF64"

cp "$TMP/good" "$TMP/x86"
printf '\003' | dd of="$TMP/x86" bs=1 seek=18 conv=notrunc 2>/dev/null
if uu_check_mipsel_24kc_elf "$TMP/x86"; then fail "non-MIPS ELF accepted"; fi
ok "reject non-MIPS machine"

cp "$TMP/good" "$TMP/mipsr1"
printf '\120' | dd of="$TMP/mipsr1" bs=1 seek=39 conv=notrunc 2>/dev/null
if uu_check_mipsel_24kc_elf "$TMP/mipsr1"; then fail "non-MIPS32r2 ISA accepted"; fi
ok "reject wrong MIPS ISA"

dd if="$TMP/good" of="$TMP/truncated" bs=1 count=20 2>/dev/null
if uu_check_mipsel_24kc_elf "$TMP/truncated"; then fail "truncated ELF accepted"; fi
ok "reject truncated ELF"

cp "$TMP/x86" "$TMP/stage/files/xuplugin-guardian"
if uu_check_stage_mipsel_elf "$TMP/stage" >/dev/null 2>&1; then
    fail "stage containing wrong-architecture guardian accepted"
fi
ok "reject stage with mismatched guardian"

# Simulate minimal OpenWrt: od command exists but is not functional, while
# BusyBox-compatible hexdump is present. The ELF check must use the fallback.
(
    od() { return 127; }
    hexdump() {
        /usr/bin/od -An -tx1 -j "$3" -N "$5" "$8" | /usr/bin/tr -d '[:space:]'
    }
    uu_check_mipsel_24kc_elf "$TMP/good" || exit 1
) || fail "fallback to hexdump failed when od is unavailable"
ok "hexdump fallback works without functional od"

# Missing both readers must fail before staging downloads anything.
mkdir -p "$TMP/minimal-bin"
ln -s "$(command -v dirname)" "$TMP/minimal-bin/dirname"
out=$(PATH="$TMP/minimal-bin" UU_STAGE_DIR="/tmp/uu-wol-helper-elf-noreader-$$" /bin/sh "$ROOT_DIR/scripts/stage-package.sh" openwrt-mipsel 2>&1)
rc=$?
if [ "$rc" -ne 4 ] || ! printf '%s\n' "$out" | grep -F "MIPS stage requires od or hexdump" >/dev/null 2>&1; then
    fail "missing reader must produce actionable pre-download error"
fi
if [ -e "/tmp/uu-wol-helper-elf-noreader-$$" ]; then
    fail "missing reader must not write stage files"
fi
ok "no reader: refuse MIPS stage before download"

printf 'all MIPS ELF guard tests passed\n'
