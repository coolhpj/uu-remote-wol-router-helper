#!/bin/sh

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd) || exit 1
# shellcheck source=../lib/netease-api.sh
. "$SCRIPT_DIR/../lib/netease-api.sh"

channel="${1:-openwrt-aarch64}"

if ! uu_api_fetch_and_parse "$channel"; then
    echo "UU API check failed for channel: $channel" >&2
    exit 1
fi

printf '%s\n' "UU API check"
printf '%s\n' "============"
printf 'channel: %s\n' "$channel"
printf 'status: %s\n' "$UU_API_STATUS"
printf 'version: %s\n' "$UU_API_VERSION"
printf 'md5: %s\n' "$UU_API_MD5"
printf 'url: %s\n' "$UU_API_URL"
if [ -n "$UU_API_URL_BAK" ]; then
    printf 'url_bak: %s\n' "$UU_API_URL_BAK"
fi
if [ -n "$UU_API_SIGNATURE" ]; then
    printf 'signature: present\n'
else
    printf 'signature: absent\n'
fi
