#!/bin/sh

xq_join_root() {
    root="$1"
    path="$2"
    if [ "$root" = "/" ]; then
        printf '%s\n' "$path"
    else
        printf '%s%s\n' "${root%/}" "$path"
    fi
}

xq_validate_target_root() {
    root="$1"
    case "$root" in
        /) return 0 ;;
        /tmp/uu-wol-helper-root-*)
            [ "${UU_TEST_MODE:-0}" = "1" ]
            return $?
            ;;
        *) return 1 ;;
    esac
}

xq_plugin_dir() { xq_join_root "$1" /userdisk/appdata/2882303761518031252; }
xq_helper_dir() { xq_join_root "$1" /data/uu-v14; }
xq_state_dir() { xq_join_root "$1" /data/uu-wol-helper-state; }
xq_install_json() { xq_join_root "$1" /userdisk/appdata/installPlugin/2882303761518031252.json; }

xq_runtime_active() {
    ps 2>/dev/null | grep '[u]uplugin ' >/dev/null 2>&1 && return 0
    ps 2>/dev/null | grep '[x]uplugin-guardian' >/dev/null 2>&1 && return 0
    ps 2>/dev/null | grep '[u]uplugin_monitor' >/dev/null 2>&1 && return 0
    return 1
}

xq_legacy_metadata_ready() {
    root="$1"
    plugin_dir=$(xq_plugin_dir "$root")
    install_json=$(xq_install_json "$root")

    [ -f "$plugin_dir/manifest" ] || return 1
    [ -f "$plugin_dir/start_script" ] || return 1
    [ -f "$install_json" ] || return 1
    grep 'xnetease-uu' "$plugin_dir/start_script" >/dev/null 2>&1 || return 1
    return 0
}

xq_is_managed_helper() {
    root="$1"
    helper_dir=$(xq_helper_dir "$root")
    [ -f "$helper_dir/install.meta" ] || return 1
    grep '^managed_by=uu-remote-wol-router-helper$' "$helper_dir/install.meta" >/dev/null 2>&1
}
