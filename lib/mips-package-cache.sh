#!/bin/sh
# Optional, bounded Y1 flash cache of the official compressed archive.
# Source only after checksum.sh and archive.sh. Never store unpacked executables.
uu_cache_path() {
    UU_CACHE_DIR=/etc/uu-mips-wol-helper
    if [ "${UU_TEST_MODE:-0}" = 1 ]; then
        UU_CACHE_DIR="${UU_MIPS_STATE_DIR:-/tmp/uu-wol-helper-state-test}"
    fi
    UU_CACHE_ARCHIVE="$UU_CACHE_DIR/uu.tar.gz"
}
uu_cache_safe_dir() {
    [ ! -L "$UU_CACHE_DIR" ] || return 1
    if [ ! -d "$UU_CACHE_DIR" ]; then
        [ ! -e "$UU_CACHE_DIR" ] || return 1
        ( umask 077; mkdir -m 700 "$UU_CACHE_DIR" ) || return 1
    fi
    [ -d "$UU_CACHE_DIR" ] && [ ! -L "$UU_CACHE_DIR" ]
}
uu_cache_valid_archive() {
    file="$1"
    expected="$2"
    [ -f "$file" ] && [ ! -L "$file" ] || return 1
    bytes=$(wc -c < "$file" 2>/dev/null) || return 1
    case "$bytes" in ''|*[!0-9]*) return 1 ;; esac
    [ "$bytes" -ge 1024 ] && [ "$bytes" -le 3670016 ] || return 1
    uu_verify_md5 "$file" "$expected" && uu_validate_uu_package "$file"
}
uu_cache_try_restore() {
    dest="$1"
    expected="$2"
    uu_cache_path
    [ ! -L "$UU_CACHE_DIR" ] || return 1
    uu_cache_valid_archive "$UU_CACHE_ARCHIVE" "$expected" || return 1
    [ ! -e "$dest" ] && [ ! -L "$dest" ] || return 1
    cp "$UU_CACHE_ARCHIVE" "$dest" || { rm -f "$dest"; return 1; }
    if ! uu_cache_valid_archive "$dest" "$expected"; then
        rm -f "$dest"
        return 1
    fi
    echo "MIPS_CACHE_VERIFIED_HIT"
}
uu_cache_try_store() {
    source="$1"
    expected="$2"
    uu_cache_path
    uu_cache_valid_archive "$source" "$expected" || return 1
    uu_cache_safe_dir || return 1
    # Existing cache is not overwritten until the new file is verified.
    if uu_cache_valid_archive "$UU_CACHE_ARCHIVE" "$expected"; then
        return 0
    fi
    [ ! -L "$UU_CACHE_ARCHIVE" ] || return 1
    if [ -e "$UU_CACHE_ARCHIVE" ]; then
        [ -f "$UU_CACHE_ARCHIVE" ] || return 1
    fi
    size_bytes=$(wc -c < "$source") || return 1
    size_kb=$(( (size_bytes + 1023) / 1024 ))
    free_kb=""
    if [ "${UU_TEST_MODE:-0}" = 1 ]; then
        free_kb="${UU_CACHE_TEST_FREE_KB:-}"
    else
        free_kb=$(df -Pk /overlay | awk 'NR==2 {print $4}') || return 1
    fi
    if [ -n "$free_kb" ]; then
        case "$free_kb" in *[!0-9]*) return 1 ;; esac
        # New file + at least 3 MiB reserved for OpenWrt and UUID state.
        [ "$free_kb" -ge "$(( size_kb + 3072 ))" ] || return 1
    fi
    tmp="$UU_CACHE_DIR/.uu-cache-new.$$"
    [ ! -e "$tmp" ] && [ ! -L "$tmp" ] || return 1
    ( umask 077; cp "$source" "$tmp" ) || { rm -f "$tmp"; return 1; }
    chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
    uu_cache_valid_archive "$tmp" "$expected" || { rm -f "$tmp"; return 1; }
    mv -f "$tmp" "$UU_CACHE_ARCHIVE" || { rm -f "$tmp"; return 1; }
    sync
    echo "MIPS_CACHE_UPDATED"
}
