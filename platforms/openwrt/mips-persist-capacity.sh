#!/bin/sh
# Read-only capacity assessment for experimental OpenWrt MIPS persistence.
# Does not write to the router, activate UU, or authorize installation.
set -u
ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/../.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/lib/channel.sh"
STAGE_DIR="${UU_STAGE_DIR:-/tmp/uu-wol-helper-stage}"
case "$STAGE_DIR" in
    /tmp/uu-wol-helper-*) ;;
    *) echo "Unsafe stage directory" >&2; exit 2 ;;
esac

echo "MIPS persistent storage assessment"
echo "=================================="
echo "mode: read-only"
echo "persistent_install: blocked"
arch=$(uu_openwrt_detect_arch 2>/dev/null || printf unknown)
printf 'architecture: %s\n' "$arch"
[ "$arch" = mipsel_24kc ] || {
    echo "result: unsupported_arch"
    exit 3
}

# Query only the available 1K blocks; no filesystem configuration is changed.
# An unparseable value is unknown, never assumed to mean enough capacity.
free_kb=$(df -k /overlay 2>/dev/null | awk '
    NR > 1 && $4 ~ /^[0-9]+$/ {value=$4}
    END {if (value != "") print value}
')
case "$free_kb" in
    ''|*[!0-9]*) free_kb=unknown ;;
esac
printf 'overlay_free_kb: %s\n' "$free_kb"

total_bytes=0
files_ok=yes
for name in uuplugin xuplugin-guardian uu.conf xtables-nft-multi; do
    file="$STAGE_DIR/files/$name"
    if [ ! -f "$file" ] || [ -L "$file" ]; then
        files_ok=no
        break
    fi
    bytes=$(wc -c < "$file" 2>/dev/null | tr -d '[:space:]')
    case "$bytes" in
        ''|*[!0-9]*) files_ok=no; break ;;
    esac
    total_bytes=$((total_bytes + bytes))
done
if [ "$files_ok" = yes ]; then
    payload_kb=$(((total_bytes + 1023) / 1024))
    # Reserve 4 MiB for system writes, metadata and filesystem overhead.
    reserve_kb=4096
    required_kb=$((payload_kb + reserve_kb))
    printf 'unpacked_payload_kb: %s\n' "$payload_kb"
    printf 'minimum_free_kb_with_reserve: %s\n' "$required_kb"
else
    echo "unpacked_payload_kb: unknown (stage files missing)"
fi

# The current generic installer additionally requires backups when replacing
# an existing installation. Never give an "enough" answer in that case.
if [ -d /usr/lib/uu-wol-helper ]; then
    echo "existing_installation: present"
    echo "direct_install_budget: unknown (backup space not assessed)"
elif [ "$files_ok" != yes ] || [ "$free_kb" = unknown ]; then
    echo "direct_install_budget: unknown"
elif [ "$free_kb" -ge "$required_kb" ]; then
    echo "direct_install_budget: capacity_only_enough"
else
    echo "direct_install_budget: insufficient"
fi
echo "decision: do_not_install (lifecycle and rollback not verified)"
