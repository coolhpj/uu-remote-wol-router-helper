#!/bin/sh

# Read-only MIPS/MT7620 runtime safety inventory.
# This is not an authorization to start UU: the generic smoke runner cannot
# yet restore all firewall state or safely scope process cleanup on this device.

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/../.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/lib/channel.sh"
. "$ROOT_DIR/lib/checksum.sh"
. "$ROOT_DIR/lib/archive.sh"
. "$ROOT_DIR/lib/elf.sh"
. "$ROOT_DIR/lib/evidence.sh"

STAGE_DIR="${UU_STAGE_DIR:-/tmp/uu-wol-helper-stage}"
case "$STAGE_DIR" in
    /tmp/uu-wol-helper-*) ;;
    *) echo "Unsafe stage directory; only /tmp/uu-wol-helper-* is allowed." >&2; exit 2 ;;
esac

printf '%s\n' "MIPS OpenWrt runtime readiness (read-only)"
printf '%s\n' "========================================="
printf '%s\n' "mode: read-only"
printf '%s\n' "persistent_changes: no"
printf '%s\n' "process_changes: no"
printf '%s\n' "firewall_changes: no"

arch=$(uu_openwrt_detect_arch 2>/dev/null || printf unknown)
printf 'architecture: %s\n' "$arch"
if [ "$arch" != "mipsel_24kc" ]; then
    echo "result: unsupported_arch"
    exit 3
fi

if sh "$ROOT_DIR/platforms/openwrt/preflight.sh" >/dev/null 2>&1; then
    echo "preflight: pass"
else
    echo "preflight: fail"
fi

stage_status="missing_or_invalid"
metadata="$STAGE_DIR/metadata"
package="$STAGE_DIR/uu.tar.gz"
if [ -r "$metadata" ] && [ -r "$package" ]; then
    stage_channel=$(sed -n 's/^channel=//p' "$metadata" | head -n 1)
    stage_md5=$(sed -n 's/^md5=//p' "$metadata" | head -n 1)
    if [ "$stage_channel" = "openwrt-mipsel" ] &&
        uu_evidence_validate_md5 "$stage_md5" &&
        uu_verify_md5 "$package" "$stage_md5" &&
        uu_validate_uu_package "$package" &&
        uu_check_stage_mipsel_elf "$STAGE_DIR" >/dev/null 2>&1; then
        stage_status="verified"
    fi
fi
printf 'stage_check: %s\n' "$stage_status"

# Only booleans are emitted; process arguments and firewall rules stay private.
if ps 2>/dev/null | grep -E '[u]uplugin|[x]uplugin-guardian|[u]uplugin_monitor|[x]netease-uu' >/dev/null 2>&1; then
    echo "existing_uu_process: yes"
else
    echo "existing_uu_process: no"
fi

if command -v fw4 >/dev/null 2>&1; then
    echo "firewall_manager: fw4"
elif command -v fw3 >/dev/null 2>&1; then
    echo "firewall_manager: fw3"
else
    echo "firewall_manager: unknown"
fi

for utility in nft iptables iptables-save ip6tables-save netstat ss killall; do
    if command -v "$utility" >/dev/null 2>&1; then
        printf 'tool_%s: present\n' "$utility"
    else
        printf 'tool_%s: absent\n' "$utility"
    fi
done

# Query table names only; never print rule listings or routing identifiers.
firewall_marker="unknown"
if command -v nft >/dev/null 2>&1; then
    tables=$(nft list tables 2>/dev/null)
    if [ "$?" -eq 0 ]; then
        if printf '%s\n' "$tables" | grep 'XU_' >/dev/null 2>&1; then
            firewall_marker="present"
        else
            firewall_marker="not_seen_in_nft_tables"
        fi
    fi
fi
printf 'xu_firewall_marker: %s\n' "$firewall_marker"

echo "runtime_test: blocked_pending_safety_review"
echo "result: inventory_only"
exit 0
