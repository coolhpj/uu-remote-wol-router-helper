#!/bin/sh

# Read-only ASUSWRT / ASUSWRT-Merlin platform detector.
# Exit 0: ASUSWRT indicators found.
# Exit 1: indicators not found.

arch=$(uname -m 2>/dev/null || printf 'unknown')
model=""
firmware=""
sw_mode=""
nvram_state="no"
JFFS_DIR="${UU_ASUS_JFFS_DIR:-/jffs}"
KOOLSHARE_DIR="${UU_ASUS_KOOLSHARE_DIR:-/koolshare}"
PERSIST_DIR="${UU_ASUS_PERSIST_DIR:-$JFFS_DIR/uu}"
RUNTIME_DIR="${UU_ASUS_RUNTIME_DIR:-/tmp/uu}"

have_cmd() {
    name="$1"
    command -v "$name" >/dev/null 2>&1 && return 0
    for dir in /bin /sbin /usr/bin /usr/sbin; do
        [ -x "$dir/$name" ] && return 0
    done
    return 1
}

if have_cmd nvram; then
    nvram_state="yes"
    model=$(nvram get productid 2>/dev/null || true)
    buildno=$(nvram get buildno 2>/dev/null || true)
    extendno=$(nvram get extendno 2>/dev/null || true)
    sw_mode=$(nvram get sw_mode 2>/dev/null || true)

    if [ -n "$buildno" ] || [ -n "$extendno" ]; then
        firmware="${buildno:-unknown}"
        if [ -n "$extendno" ] && [ "$extendno" != "0" ]; then
            firmware="$firmware / $extendno"
        fi
    fi
fi

jffs="absent"
if [ -d "$JFFS_DIR" ]; then
    if [ -w "$JFFS_DIR" ]; then
        jffs="present,writable"
    else
        jffs="present,read-only"
    fi
fi

koolshare="absent"
[ -d "$KOOLSHARE_DIR" ] && koolshare="present"

uu_persistent="absent"
[ -d "$PERSIST_DIR" ] && uu_persistent="present"

uu_runtime="absent"
[ -d "$RUNTIME_DIR" ] && uu_runtime="present"

matched="no"
case "$model" in
    RT-*|GT-*|TUF-*|XT*|ET*|XD*|BQ*|ZenWiFi*|ASUS*)
        [ -d "$JFFS_DIR" ] && matched="yes"
        ;;
esac

printf '%s\n' "ASUSWRT platform detection"
printf '%s\n' "==========================="
printf 'matched: %s\n' "$matched"
printf 'model: %s\n' "${model:-unknown}"
printf 'architecture: %s\n' "$arch"
printf 'nvram: %s\n' "$nvram_state"
printf 'firmware: %s\n' "${firmware:-unknown}"
printf 'sw_mode: %s\n' "${sw_mode:-unknown}"
printf 'jffs_dir: %s\n' "$JFFS_DIR"
printf '/jffs: %s\n' "$jffs"
printf 'koolshare: %s\n' "$koolshare"
printf 'uu_persistent: %s\n' "$uu_persistent"
printf 'uu_runtime: %s\n' "$uu_runtime"

[ "$matched" = "yes" ]
