#!/bin/sh

# NetEase UU router plugin API helper.
# This file is intentionally POSIX/BusyBox-ash friendly and does not depend on jq.

UU_API_BASE="${UU_API_BASE:-https://router.uu.163.com/api/plugin}"
UU_API_CONNECT_TIMEOUT="${UU_API_CONNECT_TIMEOUT:-8}"
UU_API_MAX_TIME="${UU_API_MAX_TIME:-20}"

UU_API_STATUS=""
UU_API_MD5=""
UU_API_URL=""
UU_API_URL_BAK=""
UU_API_SIGNATURE=""
UU_API_VERSION=""

uu_api_extract_string() {
    key="$1"
    json="$2"

    # Prefer OpenWrt jsonfilter when available. It correctly handles key order
    # and JSON escaping. XiaoQiang/OpenWrt variants do not always ship it, so
    # a flat-JSON fallback is kept for the official API response shape.
    if command -v jsonfilter >/dev/null 2>&1; then
        printf '%s' "$json" | jsonfilter -e "@.$key" 2>/dev/null
        return $?
    fi

    # The official endpoint currently returns a flat one-line object whose
    # relevant fields are simple strings. This pattern matches the exact key,
    # so `url` does not accidentally match `url_bak`, and it does not care
    # about key ordering or URL query strings containing ? / &.
    printf '%s' "$json" \
        | tr -d '\r\n' \
        | sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

uu_api_extract_version() {
    url="$1"
    version=$(printf '%s\n' "$url" | sed -n 's#^.*/\(v[0-9][^/]*\)/uu\.tar\.gz.*#\1#p')
    if [ -n "$version" ]; then
        printf '%s\n' "$version"
    else
        printf '%s\n' "unknown"
    fi
}

uu_api_validate_channel() {
    channel="$1"
    case "$channel" in
        ''|*[!A-Za-z0-9._-]*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

uu_api_validate_url() {
    url="$1"
    case "$url" in
        http://*|https://*) return 0 ;;
        *) return 1 ;;
    esac
}

uu_api_validate_md5() {
    value="$1"
    [ "${#value}" -eq 32 ] || return 1
    case "$value" in
        *[!0-9A-Fa-f]*) return 1 ;;
        *) return 0 ;;
    esac
}

uu_api_parse() {
    json="$1"

    UU_API_STATUS=$(uu_api_extract_string status "$json")
    UU_API_MD5=$(uu_api_extract_string md5 "$json" | tr 'A-F' 'a-f')
    UU_API_URL=$(uu_api_extract_string url "$json")
    UU_API_URL_BAK=$(uu_api_extract_string url_bak "$json")
    UU_API_SIGNATURE=$(uu_api_extract_string signature "$json")
    UU_API_VERSION=$(uu_api_extract_version "$UU_API_URL")

    [ "$UU_API_STATUS" = "ok" ] || return 1
    uu_api_validate_md5 "$UU_API_MD5" || return 1
    uu_api_validate_url "$UU_API_URL" || return 1

    if [ -n "$UU_API_URL_BAK" ]; then
        uu_api_validate_url "$UU_API_URL_BAK" || return 1
    fi

    return 0
}

uu_api_fetch() {
    channel="$1"
    uu_api_validate_channel "$channel" || {
        echo "Invalid UU channel: $channel" >&2
        return 2
    }

    api_url="$UU_API_BASE?type=$channel"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL \
            --connect-timeout "$UU_API_CONNECT_TIMEOUT" \
            --max-time "$UU_API_MAX_TIME" \
            "$api_url"
        return $?
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -qO- "$api_url"
        return $?
    fi

    echo "Neither curl nor wget is available." >&2
    return 127
}

uu_api_fetch_and_parse() {
    channel="$1"
    json=$(uu_api_fetch "$channel") || return $?
    uu_api_parse "$json"
}
