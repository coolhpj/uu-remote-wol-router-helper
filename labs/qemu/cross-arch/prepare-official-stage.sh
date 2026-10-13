#!/bin/sh
# Host-side acquisition: official API and same-host HTTPS archive.
# Verify checksum and package members BEFORE serving to the disposable guest.
set -eu
arch="$1"
dest="$2"
case "$arch" in
    x86_64) channel=openwrt-x86_64 ;;
    mipsel) channel=openwrt-mipsel ;;
    *) echo "Unsupported arch" >&2; exit 2 ;;
esac
[ -n "$dest" ] || { echo "Destination missing" >&2; exit 2; }
root=$(CDPATH= cd "$(dirname "$0")/../../.." && pwd) || exit 1
. "$root/lib/netease-api.sh"
. "$root/lib/checksum.sh"
. "$root/lib/archive.sh"
command -v curl >/dev/null 2>&1 || exit 2
mkdir -p "$dest"
# Both files are re-created for every single job. Never cache official blobs.
rm -f "$dest/uu.tar.gz" "$dest/expected-md5.txt"
uu_api_fetch_and_parse "$channel" || {
    echo "OFFICIAL_RELAY_API_FAILED $arch" >&2
    exit 11
}
case "$UU_API_URL" in
    http://*|https://*) secure_url=$(printf '%s\n' "$UU_API_URL" | sed 's#^http://#https://#') ;;
    *) echo "OFFICIAL_RELAY_URL_REJECTED $arch" >&2; exit 12 ;;
esac
curl -fsSL --retry 3 --retry-all-errors --retry-delay 2 \
    --connect-timeout 12 --max-time 120 "$secure_url" \
    -o "$dest/uu.tar.gz" || {
    echo "OFFICIAL_RELAY_DOWNLOAD_FAILED $arch" >&2
    exit 13
}
uu_verify_md5 "$dest/uu.tar.gz" "$UU_API_MD5" || {
    echo "OFFICIAL_RELAY_MD5_FAILED $arch" >&2
    exit 14
}
uu_validate_uu_package "$dest/uu.tar.gz" || {
    echo "OFFICIAL_RELAY_TAR_FAILED $arch" >&2
    exit 15
}
# Do not expose official URL query parameters in logs.
printf '%s  uu.tar.gz\n' "$UU_API_MD5" > "$dest/expected-md5.txt"
echo "OFFICIAL_RELAY_PREPARED $arch version=$UU_API_VERSION md5_verified=yes"
