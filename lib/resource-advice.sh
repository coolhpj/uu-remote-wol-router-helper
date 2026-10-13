#!/bin/sh
# Advisory-only storage sizing. No device I/O, writes, or install permission.
# Inputs are KiB: writable_flash, free_tmpfs, official_archive, unpacked_files.
uu_resource_advice() {
    if [ "$#" -ne 4 ]; then
        echo 'strategy: unknown'
        echo 'install_authorized: no'
        return 2
    fi
    for uu_resource_num in "$@"; do
        case "$uu_resource_num" in ''|*[!0-9]*)
            echo 'strategy: unknown'
            echo 'install_authorized: no'
            return 2 ;;
        esac
        [ "$uu_resource_num" -gt 0 ] 2>/dev/null &&
        [ "$uu_resource_num" -le 100000000 ] 2>/dev/null || {
            echo 'strategy: unknown'
            echo 'install_authorized: no'
            return 2
        }
    done

    uu_resource_flash=$1
    uu_resource_tmp=$2
    uu_resource_archive=$3
    uu_resource_unpacked=$4

    # Stage needs both archive and expanded data, plus 8 MiB headroom.
    # This does NOT estimate runtime heap/RAM requirements.
    uu_resource_tmp_required=$((uu_resource_archive + uu_resource_unpacked + 8192))
    # Safe replacement needs space for BOTH old and new payloads + 4 MiB OS reserve.
    uu_resource_direct_required=$((2 * uu_resource_unpacked + 4096))
    uu_resource_cache_required=$((2 * uu_resource_archive + 4096))

    if [ "$uu_resource_tmp" -lt "$uu_resource_tmp_required" ]; then
        uu_resource_strategy=insufficient_tmp
    elif [ "$uu_resource_flash" -lt 2048 ]; then
        uu_resource_strategy=insufficient_flash_for_bootstrap
    elif [ "$uu_resource_flash" -ge "$uu_resource_direct_required" ]; then
        uu_resource_strategy=direct_candidate
    elif [ "$uu_resource_flash" -ge "$uu_resource_cache_required" ]; then
        uu_resource_strategy=archive_cache_candidate
    else
        uu_resource_strategy=ram_download_candidate
    fi

    printf 'strategy: %s\n' "$uu_resource_strategy"
    printf 'tmp_min_kb: %s\n' "$uu_resource_tmp_required"
    printf 'flash_direct_dual_kb: %s\n' "$uu_resource_direct_required"
    printf 'flash_archive_dual_kb: %s\n' "$uu_resource_cache_required"
    echo 'runtime_ram_verified: no'
    echo 'install_authorized: no'
}
