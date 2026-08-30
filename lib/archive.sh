#!/bin/sh

uu_tar_members() {
    archive="$1"
    tar -tzf "$archive" 2>/dev/null
}

uu_tar_validate_paths() {
    archive="$1"
    members=$(uu_tar_members "$archive") || {
        echo "Unable to list tar archive." >&2
        return 1
    }

    [ -n "$members" ] || {
        echo "Tar archive is empty." >&2
        return 1
    }

    printf '%s\n' "$members" | while IFS= read -r entry; do
        case "$entry" in
            /*|../*|*/../*|*/..)
                echo "Unsafe tar member path: $entry" >&2
                exit 1
                ;;
        esac
    done
}

uu_tar_require_member() {
    archive="$1"
    required="$2"
    uu_tar_members "$archive" | grep -Fx "$required" >/dev/null 2>&1
}

uu_validate_uu_package() {
    archive="$1"

    uu_tar_validate_paths "$archive" || return 1

    for required in uuplugin xuplugin-guardian uu.conf xtables-nft-multi; do
        if ! uu_tar_require_member "$archive" "$required"; then
            echo "Required package member missing: $required" >&2
            return 1
        fi
    done

    return 0
}

uu_extract_uu_package() {
    archive="$1"
    destination="$2"

    uu_validate_uu_package "$archive" || return 1
    [ -d "$destination" ] || mkdir -p "$destination" || return 1
    tar -xzf "$archive" -C "$destination" || return 1

    for required in uuplugin xuplugin-guardian uu.conf xtables-nft-multi; do
        if [ ! -f "$destination/$required" ]; then
            echo "Extracted file missing or not regular: $required" >&2
            return 1
        fi
    done

    return 0
}
