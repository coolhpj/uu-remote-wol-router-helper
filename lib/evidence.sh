#!/bin/sh

uu_evidence_validate_stage_dir() {
    stage_dir="$1"
    case "$stage_dir" in
        /tmp/uu-wol-helper-*) return 0 ;;
        *) return 1 ;;
    esac
}

uu_evidence_validate_md5() {
    value="$1"
    [ "${#value}" -eq 32 ] || return 1
    case "$value" in
        *[!0-9A-Fa-f]*) return 1 ;;
        *) return 0 ;;
    esac
}

uu_smoke_marker_path() {
    stage_dir="$1"
    uu_evidence_validate_stage_dir "$stage_dir" || return 1
    printf '%s\n' "$stage_dir/smoke-pass"
}

uu_clear_smoke_pass() {
    stage_dir="$1"
    marker=$(uu_smoke_marker_path "$stage_dir") || return 1
    rm -f "$marker"
}

uu_write_smoke_pass() {
    stage_dir="$1"
    platform="$2"
    md5=$(printf '%s' "$3" | tr 'A-F' 'a-f')

    uu_evidence_validate_stage_dir "$stage_dir" || return 1
    uu_evidence_validate_md5 "$md5" || return 1

    case "$platform" in
        ''|*[!A-Za-z0-9._-]*) return 1 ;;
    esac

    marker=$(uu_smoke_marker_path "$stage_dir") || return 1
    umask 077
    {
        printf 'result=pass\n'
        printf 'platform=%s\n' "$platform"
        printf 'md5=%s\n' "$md5"
    } > "$marker"
}

uu_check_smoke_pass() {
    stage_dir="$1"
    expected_platform="$2"
    expected_md5=$(printf '%s' "$3" | tr 'A-F' 'a-f')

    uu_evidence_validate_stage_dir "$stage_dir" || return 1
    uu_evidence_validate_md5 "$expected_md5" || return 1

    marker=$(uu_smoke_marker_path "$stage_dir") || return 1
    [ -f "$marker" ] || return 1

    result=$(sed -n 's/^result=//p' "$marker" | head -n 1)
    platform=$(sed -n 's/^platform=//p' "$marker" | head -n 1)
    md5=$(sed -n 's/^md5=//p' "$marker" | head -n 1 | tr 'A-F' 'a-f')

    [ "$result" = "pass" ] || return 1
    [ "$platform" = "$expected_platform" ] || return 1
    [ "$md5" = "$expected_md5" ] || return 1
    return 0
}
