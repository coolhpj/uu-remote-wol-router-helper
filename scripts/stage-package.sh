#!/bin/sh

ROOT_DIR=$(CDPATH= cd "$(dirname "$0")/.." 2>/dev/null && pwd) || exit 1
. "$ROOT_DIR/lib/netease-api.sh"
. "$ROOT_DIR/lib/checksum.sh"
. "$ROOT_DIR/lib/download.sh"
. "$ROOT_DIR/lib/archive.sh"

channel="${1:-openwrt-aarch64}"
stage_dir="${UU_STAGE_DIR:-/tmp/uu-wol-helper-stage}"

case "$stage_dir" in
    /tmp/uu-wol-helper-*) ;;
    *)
        echo "Unsafe stage directory. UU_STAGE_DIR must match /tmp/uu-wol-helper-*" >&2
        exit 2
        ;;
esac

printf '%s\n' "UU official package staging"
printf '%s\n' "==========================="
printf 'channel: %s\n' "$channel"
printf 'stage_dir: %s\n' "$stage_dir"
printf '%s\n' "persistent_changes: no"
printf '%s\n' "process_changes: no"

if ! uu_api_fetch_and_parse "$channel"; then
    echo "Unable to query or validate the NetEase UU API response." >&2
    exit 1
fi

printf 'api_status: %s\n' "$UU_API_STATUS"
printf 'version: %s\n' "$UU_API_VERSION"
printf 'md5: %s\n' "$UU_API_MD5"

rm -rf "$stage_dir"
mkdir -p "$stage_dir/files" || exit 1
package="$stage_dir/uu.tar.gz"

if ! uu_download_with_fallback "$UU_API_URL" "$UU_API_URL_BAK" "$package"; then
    exit 1
fi

if ! uu_verify_md5 "$package" "$UU_API_MD5"; then
    echo "Official package MD5 verification failed." >&2
    exit 1
fi
printf '%s\n' "md5_check: pass"

metadata="$stage_dir/metadata"
printf 'channel=%s\nversion=%s\nmd5=%s\n' "$channel" "$UU_API_VERSION" "$UU_API_MD5" > "$metadata"

if ! uu_validate_uu_package "$package"; then
    echo "Official package structure validation failed." >&2
    exit 1
fi
printf '%s\n' "archive_check: pass"

if ! uu_extract_uu_package "$package" "$stage_dir/files"; then
    echo "Official package extraction failed." >&2
    exit 1
fi
printf '%s\n' "extract_check: pass"

printf '%s\n' "staged_files:"
for file in uuplugin xuplugin-guardian uu.conf xtables-nft-multi; do
    size=$(wc -c < "$stage_dir/files/$file" 2>/dev/null || printf 'unknown')
    printf '  %s (%s bytes)\n' "$file" "$size"
done

printf '%s\n' "STAGE_READY"
printf '%s\n' "No plugin process was stopped or started. No persistent path was modified."
