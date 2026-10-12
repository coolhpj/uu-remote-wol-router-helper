#!/bin/sh
# Build-specific distribution guard. Full source checkout remains unrestricted.
# This is an additional fail-closed front-end gate, not a substitute for install guards.
uu_package_check() {
    pkg_root="$1"
    pkg_file="$pkg_root/lib/package-profile"
    [ -r "$pkg_file" ] || {
        echo "Package profile is missing; refusing platform-specific operations" >&2
        return 67
    }
    pkg_platform=$(sed -n 's/^platform=//p' "$pkg_file" | head -n 1)
    pkg_arch=$(sed -n 's/^architecture=//p' "$pkg_file" | head -n 1)
    pkg_model=$(sed -n 's/^model=//p' "$pkg_file" | head -n 1)
    [ "$pkg_platform" = all ] && return 0

    detected=unknown
    if sh "$pkg_root/platforms/xiaoqiang/detect.sh" >/dev/null 2>&1; then
        detected=xiaoqiang
    elif sh "$pkg_root/platforms/asuswrt/detect.sh" >/dev/null 2>&1; then
        detected=asuswrt
    elif sh "$pkg_root/platforms/openwrt/detect.sh" >/dev/null 2>&1; then
        detected=openwrt
    fi
    if [ "$detected" != "$pkg_platform" ]; then
        printf 'Package targets %s but router identifies as %s; stop.\n' "$pkg_platform" "$detected" >&2
        return 67
    fi
    [ "$pkg_arch" = any ] && return 0

    if [ "$pkg_platform" = openwrt ]; then
        detected_arch=$(uu_openwrt_detect_arch 2>/dev/null || printf unknown)
    else
        detected_arch=$(uname -m 2>/dev/null || printf unknown)
    fi
    case "$pkg_arch:$detected_arch" in
        x86_64:x86_64|aarch64:aarch64|aarch64:arm64|mipsel_24kc:mipsel_24kc) ;;
        *) printf 'Package architecture %s does not match router %s; stop.\n' "$pkg_arch" "$detected_arch" >&2; return 67 ;;
    esac

    if [ "$pkg_model" = lenovo-y1 ]; then
        model=$(cat /tmp/sysinfo/model 2>/dev/null || true)
        case "$model" in
            *"Lenovo Y1"*|*"Newifi mini R6830"*) ;;
            *) printf 'Experimental package is limited to Lenovo Y1 / R6830; stop.\n' >&2; return 67 ;;
        esac
        target=$(sed -n 's/^DISTRIB_TARGET=//p' /etc/openwrt_release 2>/dev/null | tr -d "'\"")
        [ "$target" = ramips/mt7620 ] || {
            echo "Lenovo Y1 beta requires ramips/mt7620; stop." >&2
            return 67
        }
    fi
    return 0
}
