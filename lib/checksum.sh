#!/bin/sh

uu_md5_file() {
    file="$1"

    if command -v md5sum >/dev/null 2>&1; then
        output=$(md5sum "$file") || return $?
        printf '%s\n' "${output%% *}"
        return 0
    fi

    if command -v busybox >/dev/null 2>&1; then
        output=$(busybox md5sum "$file" 2>/dev/null) || return $?
        printf '%s\n' "${output%% *}"
        return 0
    fi

    echo "No md5sum implementation is available." >&2
    return 127
}

uu_verify_md5() {
    file="$1"
    expected=$(printf '%s' "$2" | tr 'A-F' 'a-f')

    [ -f "$file" ] || {
        echo "File not found: $file" >&2
        return 2
    }

    [ "${#expected}" -eq 32 ] || {
        echo "Invalid expected MD5 length." >&2
        return 2
    }

    case "$expected" in
        *[!0-9a-f]*)
            echo "Invalid expected MD5 value." >&2
            return 2
            ;;
    esac

    actual=$(uu_md5_file "$file") || return $?
    actual=$(printf '%s' "$actual" | tr 'A-F' 'a-f')

    if [ "$actual" != "$expected" ]; then
        echo "MD5 mismatch: expected=$expected actual=$actual" >&2
        return 1
    fi

    return 0
}
