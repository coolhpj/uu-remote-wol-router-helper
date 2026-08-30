#!/bin/sh

ow_join_root() {
    root="$1"
    path="$2"
    if [ "$root" = "/" ]; then
        printf '%s\n' "$path"
    else
        printf '%s%s\n' "${root%/}" "$path"
    fi
}

ow_validate_target_root() {
    root="$1"
    case "$root" in
        /)
            return 0
            ;;
        /tmp/uu-wol-helper-root-*)
            [ "${UU_TEST_MODE:-0}" = "1" ]
            return $?
            ;;
        *)
            return 1
            ;;
    esac
}

ow_install_dir() {
    ow_join_root "$1" /usr/lib/uu-wol-helper
}

ow_init_path() {
    ow_join_root "$1" /etc/init.d/uu-wol-helper
}

ow_state_dir() {
    ow_join_root "$1" /etc/uu-wol-helper
}

ow_is_managed_install() {
    root="$1"
    install_dir=$(ow_install_dir "$root")
    [ -f "$install_dir/install.meta" ] || return 1
    grep '^managed_by=uu-remote-wol-router-helper$' "$install_dir/install.meta" >/dev/null 2>&1
}

ow_is_managed_init() {
    root="$1"
    init_path=$(ow_init_path "$root")
    [ -f "$init_path" ] || return 1
    grep '^# managed_by=uu-remote-wol-router-helper$' "$init_path" >/dev/null 2>&1
}

ow_runtime_active() {
    ps 2>/dev/null | grep '[u]uplugin ' >/dev/null 2>&1 && return 0
    ps 2>/dev/null | grep '[x]uplugin-guardian' >/dev/null 2>&1 && return 0
    ps 2>/dev/null | grep '[u]uplugin_monitor' >/dev/null 2>&1 && return 0
    return 1
}

ow_service_was_enabled() {
    root="$1"
    rc_dir=$(ow_join_root "$root" /etc/rc.d)
    [ -d "$rc_dir" ] || return 1
    for link in "$rc_dir"/S*uu-wol-helper; do
        [ -e "$link" ] && return 0
    done
    return 1
}
