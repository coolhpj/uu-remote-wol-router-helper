#!/bin/sh
# Lenovo Y1 identity observation only: no writes, network, process control,
# credential contents, hashes, tokens or command-line arguments are emitted.
set -u

PREFIX=
PROC_ROOT=/proc
if [ "${UU_TEST_MODE:-0}" = 1 ]; then
    case "${UU_DIAG_TEST_ROOT:-}" in
        /tmp/uu-wol-helper-root-*) PREFIX="$UU_DIAG_TEST_ROOT" ;;
        *) echo 'MIPS_IDENTITY_OBSERVE_INVALID_TEST_ROOT' >&2; exit 64 ;;
    esac
    PROC_ROOT="$PREFIX/proc"
fi

echo 'MIPS identity location observation'
echo '=================================='
echo 'mode: read-only'
echo 'device_identity_values: never_collected'
echo 'device_identity_hashes: never_collected'
echo 'configuration_changes: no'
echo 'plugin_process_changes: no'

baseline_path=
baseline_label=
file_count=0
identity_probe() {
    label="$1"
    file="$PREFIX$2"
    if [ -L "$file" ]; then
        printf '%s: symlink_not_followed\n' "$label"
        return
    fi
    if [ ! -e "$file" ]; then
        printf '%s: absent\n' "$label"
        return
    fi
    if [ ! -f "$file" ] || [ ! -r "$file" ]; then
        printf '%s: unsupported_or_unreadable\n' "$label"
        return
    fi
    bytes=$(wc -c < "$file" 2>/dev/null) || {
        printf '%s: size_unavailable\n' "$label"
        return
    }
    case "$bytes" in ''|*[!0-9]*)
        printf '%s: size_unavailable\n' "$label"
        return
        ;;
    esac
    file_count=$((file_count + 1))
    if [ "$bytes" -ge 8 ] && [ "$bytes" -le 256 ]; then
        printf '%s: present size_bytes=%s\n' "$label" "$bytes"
        if [ -z "$baseline_path" ]; then
            baseline_path="$file"
            baseline_label="$label"
        else
            if cmp -s "$baseline_path" "$file"; then
                printf 'compare_%s_to_%s: same\n' "$baseline_label" "$label"
            else
                printf 'compare_%s_to_%s: different\n' "$baseline_label" "$label"
            fi
        fi
    else
        printf '%s: unexpected_size_bytes=%s\n' "$label" "$bytes"
    fi
}

identity_probe 'managed_ram' '/tmp/uu-wol-helper-mips-persist/files/.uuplugin_uuid'
identity_probe 'official_dir' '/usr/sbin/uu/.uuplugin_uuid'
identity_probe 'tmp_uu' '/tmp/uu/.uuplugin_uuid'
identity_probe 'root_home' '/root/.uuplugin_uuid'
identity_probe 'root_fs' '/.uuplugin_uuid'
identity_probe 'managed_flash' '/etc/uu-mips-wol-helper/.uuplugin_uuid'
printf 'candidate_file_count: %s\n' "$file_count"

uu_process_count=0
for comm in "$PROC_ROOT"/[0-9]*/comm; do
    [ -r "$comm" ] || continue
    IFS= read -r proc_name < "$comm" || continue
    [ "$proc_name" = uuplugin ] || continue
    uu_process_count=$((uu_process_count + 1))
    cwd_link=${comm%/comm}/cwd
    cwd=$(readlink "$cwd_link" 2>/dev/null || :)
    case "$cwd" in
        "$PREFIX/tmp/uu-wol-helper-mips-persist/files") cwd_category=managed_ram ;;
        "$PREFIX/usr/sbin/uu") cwd_category=official_dir ;;
        "$PREFIX/tmp/uu") cwd_category=tmp_uu ;;
        "$PREFIX/root") cwd_category=root_home ;;
        "$PREFIX/") cwd_category=root_fs ;;
        '') cwd_category=unavailable ;;
        *) cwd_category=other_redacted ;;
    esac
    printf 'uuplugin_cwd_%s: %s\n' "$uu_process_count" "$cwd_category"
done
printf 'uuplugin_process_count: %s\n' "$uu_process_count"
echo 'result: observation_only_not_binding_proof'
