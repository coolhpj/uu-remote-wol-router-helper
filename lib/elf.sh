#!/bin/sh

# Minimal ELF header verification using BusyBox-friendly od and tr.
# The OpenWrt MIPS24K candidate requires 32-bit little-endian MIPS32r2.
# This checks file format only; it cannot prove real-device runtime health.

uu_elf_hex() {
    od -An -tx1 -j "$2" -N "$3" "$1" 2>/dev/null | tr -d '[:space:]'
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
    for uu_elf_member in uuplugin xuplugin-guardian xtables-nft-multi; do
        if ! uu_check_mipsel_24kc_elf "$uu_elf_stage_dir/files/$uu_elf_member"; then
            printf 'MIPS ELF format/ISA mismatch: %s\n' "$uu_elf_member" >&2
            return 1
        fi
    done
    return 0
}
