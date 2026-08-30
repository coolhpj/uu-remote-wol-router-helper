#!/bin/sh

UU_DOWNLOAD_CONNECT_TIMEOUT="${UU_DOWNLOAD_CONNECT_TIMEOUT:-8}"
UU_DOWNLOAD_MAX_TIME="${UU_DOWNLOAD_MAX_TIME:-90}"

uu_redact_url() {
    url="$1"
    case "$url" in
        *\?*) printf '%s?<redacted>\n' "${url%%\?*}" ;;
        *) printf '%s\n' "$url" ;;
    esac
}

uu_download_url() {
    url="$1"
    destination="$2"
    part="${destination}.part.$$"

    rm -f "$part"

    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL \
            --connect-timeout "$UU_DOWNLOAD_CONNECT_TIMEOUT" \
            --max-time "$UU_DOWNLOAD_MAX_TIME" \
            "$url" -o "$part"; then
            mv "$part" "$destination"
            return 0
        fi
        rm -f "$part"
        return 1
    fi

    if command -v wget >/dev/null 2>&1; then
        if wget -qO "$part" "$url"; then
            mv "$part" "$destination"
            return 0
        fi
        rm -f "$part"
        return 1
    fi

    echo "Neither curl nor wget is available." >&2
    rm -f "$part"
    return 127
}

uu_download_with_fallback() {
    primary="$1"
    backup="$2"
    destination="$3"

    printf 'download_primary: %s\n' "$(uu_redact_url "$primary")"
    if uu_download_url "$primary" "$destination"; then
        printf '%s\n' "download_source: primary"
        return 0
    fi

    [ -n "$backup" ] || {
        echo "Primary download failed and no backup URL is available." >&2
        return 1
    }

    printf 'download_backup: %s\n' "$(uu_redact_url "$backup")"
    if uu_download_url "$backup" "$destination"; then
        printf '%s\n' "download_source: backup"
        return 0
    fi

    echo "Both primary and backup downloads failed." >&2
    return 1
}
