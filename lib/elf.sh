#!/bin/sh

# Minimal ELF header verification using od, hexdump, or BusyBox hexdump.
# The OpenWrt MIPS24K candidate requires 32-bit little-endian MIPS32r2.
# This checks file format only; it cannot prove real-device runtime health.

uu_elf_have_hex_reader() {
    command -v od >/dev/null 2>&1 && return 0
    command -v hexdump >/dev/null 2>&1 && return 0
    if command -v busybox >/dev/null 2>&1; then
        busybox --list 2>/dev/null | grep -qx hexdump && return 0
    fi
    return 1
}

uu_elf_hex() {
    uu_hex_file="$1"
    uu_hex_skip="$2"
    uu_hex_count="$3"
    uu_hex_expected=$((uu_hex_count * 2))

    if command -v od >/dev/null 2>&1; then
        uu_hex_value=$(od -An -tx1 -j "$uu_hex_skip" -N "$uu_hex_count" "$uu_hex_file" 2>/dev/null | tr -d '[:space:]')
        if [ "${#uu_hex_value}" -eq "$uu_hex_expected" ]; then
            printf '%s\n' "$uu_hex_value"
            return 0
        fi
    fi

    if command -v hexdump >/dev/null 2>&1; then
        uu_hex_value=$(hexdump -v -s "$uu_hex_skip" -n "$uu_hex_count" -e '1/1 "%02x"' "$uu_hex_file" 2>/dev/null)
        if [ "${#uu_hex_value}" -eq "$uu_hex_expected" ]; then
            printf '%s\n' "$uu_hex_value"
            return 0
        fi
    fi

    if command -v busybox >/dev/null 2>&1 && busybox --list 2>/dev/null | grep -qx hexdump; then
        uu_hex_value=$(busybox hexdump -v -s "$uu_hex_skip" -n "$uu_hex_count" -e '1/1 "%02x"' "$uu_hex_file" 2>/dev/null)
        if [ "${#uu_hex_value}" -eq "$uu_hex_expected" ]; then
            printf '%s\n' "$uu_hex_value"
            return 0
        fi
    fi
    return 1
}

uu_check_mipsel_24kc_elf() {
    uu_elf_candidate="$1"
    [ -f "$uu_elf_candidate" ] && [ -r "$uu_elf_candidate" ] || return 1
    [ "$(uu_elf_hex "$uu_elf_candidate" 0 4)" = "7f454c46" ] || return 1
    # EI_CLASS=1 (ELF32), EI_DATA=1 (little-endian).
    [ "$(uu_elf_hex "$uu_elf_candidate" 4 2)" = "0101" ] || return 1
    # e_machine=8 (EM_MIPS), stored little-endian.
    [ "$(uu_elf_hex "$uu_elf_candidate" 18 2)" = "0800" ] || return 1
    # e_flags upper nibble 7: EF_MIPS_ARCH_32R2 (MIPS32 release 2).
    # Do not rely on the remainder of the flags, which can vary by build.
    case "$(uu_elf_hex "$uu_elf_candidate" 36 4)" in
        ??????7?) return 0 ;;
        *) return 1 ;;
    esac
}

uu_check_stage_mipsel_elf() {
    uu_elf_stage_dir="$1"
    if ! uu_elf_have_hex_reader; then
        echo "MIPS ELF inspector unavailable: install neither package nor runtime; need od or hexdump." >&2
        return 2
    fi
    for uu_elf_member in uuplugin xuplugin-guardian xtables-nft-multi; do
        if ! uu_check_mipsel_24kc_elf "$uu_elf_stage_dir/files/$uu_elf_member"; then
            printf 'MIPS ELF format/ISA mismatch: %s\n' "$uu_elf_member" >&2
            return 1
        fi
    done
    return 0
}
