#!/bin/sh
# Lenovo Y1: preserve the official plugin's opaque device identifier.
# Never log, print or synthesize the identifier. This module is sourced.
umask 077

uu_uuid_paths() {
    UU_UUID_RUNTIME_DIR=/tmp/uu-wol-helper-mips-persist/files
    UU_UUID_STATE_DIR=/etc/uu-mips-wol-helper
    if [ "${UU_TEST_MODE:-0}" = 1 ]; then
        UU_UUID_RUNTIME_DIR="${UU_MIPS_STAGE_DIR:-/tmp/uu-wol-helper-mips-persist}/files"
        UU_UUID_STATE_DIR="${UU_MIPS_STATE_DIR:-/tmp/uu-wol-helper-state-test}"
    fi
    UU_UUID_RUNTIME="$UU_UUID_RUNTIME_DIR/.uuplugin_uuid"
    UU_UUID_STORED="$UU_UUID_STATE_DIR/.uuplugin_uuid"
}

uu_uuid_valid() {
    [ -f "$1" ] && [ ! -L "$1" ] || return 1
    uuid_bytes=$(wc -c < "$1" 2>/dev/null) || return 1
    case "$uuid_bytes" in ''|*[!0-9]*) return 1 ;; esac
    [ "$uuid_bytes" -ge 8 ] && [ "$uuid_bytes" -le 256 ]
}

uu_uuid_state_dir_safe() {
    [ ! -L "$UU_UUID_STATE_DIR" ] || return 1
    if [ ! -d "$UU_UUID_STATE_DIR" ]; then
        [ ! -e "$UU_UUID_STATE_DIR" ] || return 1
        mkdir -m 700 "$UU_UUID_STATE_DIR" || return 1
    fi
    [ -d "$UU_UUID_STATE_DIR" ] && [ ! -L "$UU_UUID_STATE_DIR" ]
}

uu_uuid_preserve_before_stage() {
    uu_uuid_paths
    # A procd restart can occur before the asynchronous watcher catches the
    # newly created UUID. Rescue it before stage-package removes the RAM tree.
    if [ ! -e "$UU_UUID_RUNTIME" ] && [ ! -L "$UU_UUID_RUNTIME" ]; then
        return 0
    fi
    uu_uuid_valid "$UU_UUID_RUNTIME" || return 1
    if [ -e "$UU_UUID_STORED" ] || [ -L "$UU_UUID_STORED" ]; then
        uu_uuid_valid "$UU_UUID_STORED" &&
            cmp -s "$UU_UUID_RUNTIME" "$UU_UUID_STORED" || return 1
        return 0
    fi
    uu_uuid_backup_once
}

uu_uuid_initial_capacity_guard() {
    uu_uuid_paths
    # Do not permit a first new binding on read-only/nearly-full flash.
    # Previously saved identifiers are validated by uu_uuid_restore.
    if [ -e "$UU_UUID_STORED" ] || [ -L "$UU_UUID_STORED" ]; then
        uu_uuid_valid "$UU_UUID_STORED"
        return $?
    fi
    if [ "${UU_TEST_MODE:-0}" = 1 ]; then
        available_kb="${UU_UUID_TEST_FREE_KB:-4096}"
    else
        available_kb=$(df -Pk /overlay | awk 'NR==2 {print $4}') || return 1
    fi
    case "$available_kb" in ''|*[!0-9]*) return 1 ;; esac
    [ "$available_kb" -ge 1024 ]
}

uu_uuid_restore() {
    uu_uuid_paths
    if [ ! -e "$UU_UUID_STORED" ] && [ ! -L "$UU_UUID_STORED" ]; then
        echo "MIPS_UUID_FIRST_BIND_PENDING"
        return 0
    fi
    uu_uuid_valid "$UU_UUID_STORED" || {
        echo "MIPS_UUID_STORED_INVALID: refusing to launch with a new identity" >&2
        return 1
    }
    [ -d "$UU_UUID_RUNTIME_DIR" ] && [ ! -L "$UU_UUID_RUNTIME_DIR" ] &&
        [ ! -e "$UU_UUID_RUNTIME" ] && [ ! -L "$UU_UUID_RUNTIME" ] || return 1
    [ ! -L "$UU_UUID_STATE_DIR" ] || return 1
    cp "$UU_UUID_STORED" "$UU_UUID_RUNTIME" || return 1
    chmod 600 "$UU_UUID_RUNTIME" || return 1
    echo "MIPS_UUID_RESTORED"
}

uu_uuid_backup_once() {
    uu_uuid_paths
    [ -d "$UU_UUID_RUNTIME_DIR" ] && [ ! -L "$UU_UUID_RUNTIME_DIR" ] || return 1
    uu_uuid_valid "$UU_UUID_RUNTIME" || return 1
    if [ -e "$UU_UUID_STORED" ] || [ -L "$UU_UUID_STORED" ]; then
        uu_uuid_valid "$UU_UUID_STORED" || {
            echo "MIPS_UUID_STORED_INVALID: original identity retained" >&2
            return 2
        }
        if cmp -s "$UU_UUID_RUNTIME" "$UU_UUID_STORED"; then
            return 0
        fi
        echo "MIPS_UUID_CONFLICT: stored identity will not be overwritten" >&2
        return 2
    fi
    uu_uuid_state_dir_safe || return 2
    if [ "${UU_TEST_MODE:-0}" != 1 ]; then
        available_kb=$(df -Pk /overlay | awk 'NR==2 {print $4}') || return 2
        case "$available_kb" in ''|*[!0-9]*) return 2 ;; esac
        [ "$available_kb" -ge 1024 ] || return 2
    fi
    tmp="$UU_UUID_STATE_DIR/.uuid-new.$$"
    [ ! -e "$tmp" ] && [ ! -L "$tmp" ] || return 2
    cp "$UU_UUID_RUNTIME" "$tmp" || { rm -f "$tmp"; return 2; }
    chmod 600 "$tmp" || { rm -f "$tmp"; return 2; }
    uu_uuid_valid "$tmp" && cmp -s "$UU_UUID_RUNTIME" "$tmp" || {
        rm -f "$tmp"
        return 2
    }
    # Only this script owns the state path. Never overwrite an existing ID.
    [ ! -e "$UU_UUID_STORED" ] && [ ! -L "$UU_UUID_STORED" ] || {
        rm -f "$tmp"
        return 2
    }
    # Two procd workers may race between the existence check and this write.
    # ln creates the destination name atomically without replacing a saved ID;
    # a plain mv would silently overwrite a concurrent writer's binding.
    if ! ln "$tmp" "$UU_UUID_STORED"; then
        rm -f "$tmp"
        if uu_uuid_valid "$UU_UUID_STORED" && cmp -s "$UU_UUID_RUNTIME" "$UU_UUID_STORED"; then
            return 0
        fi
        echo "MIPS_UUID_CONFLICT: concurrent binding will not replace original" >&2
        return 2
    fi
    sync
    rm -f "$tmp"
    echo "MIPS_UUID_BACKUP_SAVED"
    return 0
}
